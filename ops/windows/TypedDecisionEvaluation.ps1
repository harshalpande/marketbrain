# Pure evaluation helpers. Importing this file does not contact services or run a model.
function Get-TypedResponseObject {
    param([string]$Text, [string]$Prompt)
    $result = [pscustomobject]@{ version='TYPED_RESPONSE_EXTRACTOR_V2'; json=$null; error=$null; echoRemoved=$false; objectCount=0 }
    if ($Text.Length -gt 1048576) { $result.error='RESPONSE_TOO_LARGE'; return $result }
    $clean = [regex]::Replace($Text, '\x1b\[[0-?]*[ -/]*[@-~]', '').Replace("`r`n", "`n").TrimStart([char]0xfeff)
    $normalizedPrompt = $Prompt.Replace("`r`n", "`n").Trim()
    $echo = [regex]::Match($clean, '(?m)^> ')
    if ($echo.Success) {
        $tail = $clean.Substring($echo.Index + $echo.Length)
        if ($normalizedPrompt.Length -gt 0 -and $tail.StartsWith($normalizedPrompt, [StringComparison]::Ordinal)) {
            $clean = $tail.Substring($normalizedPrompt.Length)
        } else {
            $truncated = $tail.IndexOf(' ... (truncated)', [StringComparison]::Ordinal)
            if ($truncated -le 0 -or -not $normalizedPrompt.StartsWith($tail.Substring(0,$truncated), [StringComparison]::Ordinal)) {
                $result.error='UNRECOGNIZED_PROMPT_ECHO'; return $result
            }
            $clean = $tail.Substring($truncated + ' ... (truncated)'.Length)
        }
        $result.echoRemoved=$true
    }
    # Restart at each plausible object opening: an unmatched brace in a log must not hide a later answer.
    # Never choose by expected decision, candidate ID, or business validity; multiple objects fail closed.
    $objects = @()
    if ($clean -match '(?m)^\s*\[\s*\{') { $result.error='JSON_ARRAY_NOT_OBJECT'; return $result }
    $starts = [regex]::Matches($clean, '\{\s*(?=["}])')
    if ($starts.Count -gt 128) { $result.error='TOO_MANY_OBJECT_STARTS'; return $result }
    $consumedThrough=-1
    foreach ($start in $starts) {
        if ($start.Index -le $consumedThrough) { continue }
        $depth=0; $quoted=$false; $escaped=$false
        $endLimit=[Math]::Min($clean.Length, $start.Index + 65536)
        for ($i=$start.Index; $i -lt $endLimit; $i++) {
            $ch=$clean[$i]
            if ($quoted) {
                if ($escaped) { $escaped=$false }
                elseif ($ch -eq '\') { $escaped=$true }
                elseif ($ch -eq '"') { $quoted=$false }
                continue
            }
            if ($ch -eq '"') { $quoted=$true }
            elseif ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $json=$clean.Substring($start.Index,$i-$start.Index+1)
                    try {
                        $value=ConvertFrom-Json -InputObject $json -ErrorAction Stop
                        if ($value -is [pscustomobject]) { $objects += $json; $consumedThrough=$i }
                    } catch { }
                    break
                }
            }
        }
    }
    $result.objectCount=$objects.Count
    if ($objects.Count -eq 0) { $result.error='NO_JSON_OBJECT_FOUND' }
    elseif ($objects.Count -ne 1) { $result.error='AMBIGUOUS_JSON_OBJECTS' }
    else { $result.json=$objects[0] }
    return $result
}

function Test-TypedDecisionResponse {
    param([string]$Text, [string]$Prompt, [object]$Candidate, [int]$ExitCode, [bool]$TimedOut,
        [string]$EvaluationMode='INDEPENDENT')
    $extraction=Get-TypedResponseObject -Text $Text -Prompt $Prompt
    $failures=@(); $warnings=@(); $decision=$null; $parseable=$false; $schema=$false
    $allowed=[ordered]@{
        candidateId=@([string]$Candidate.candidateId)
        decision=@('REJECT','WATCHLIST','SHORTLIST','TOP_PICK')
        riskBucket=@('LOW','MEDIUM','HIGH','BLOCKED'); trapDetected=@('YES','NO')
        scoreBand=@('VERY_LOW','LOW','MEDIUM','HIGH','VERY_HIGH'); confidenceBand=@('LOW','MEDIUM','HIGH')
        primaryReasonCode=@('WEAK_TREND','STRONG_MOMENTUM','TRAP_RISK','RELATIVE_STRENGTH','RISK_ADJUSTED_LEADER','JAVA_BASELINE_ALIGNED','BLOCKED_BY_RISK','RECOVERY_SETUP','OVEREXTENSION_RISK','MIXED_EVIDENCE')
    }
    if ($extraction.error) { $failures += $extraction.error }
    else {
        $decision=ConvertFrom-Json -InputObject $extraction.json
        $parseable=$true
        $keys=@($decision.PSObject.Properties.Name)
        # The contract is flat and string-only. Preserve duplicate-key evidence before ConvertFrom-Json collapses it.
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($keyMatch in [regex]::Matches($extraction.json, '(?:\{|,)\s*"(?<key>(?:\\.|[^"\\])*)"\s*:')) {
            $key=ConvertFrom-Json -InputObject ('"' + $keyMatch.Groups['key'].Value + '"')
            if (-not $seen.Add($key)) { $failures += "DUPLICATE_KEY_$key" }
        }
        foreach ($key in $allowed.Keys) {
            if ($keys -cnotcontains $key) {
                $failures += "MISSING_KEY_$key"
                $decision | Add-Member -NotePropertyName $key -NotePropertyValue $null -Force
            }
            if ($decision.$key -isnot [string] -or $allowed[$key] -cnotcontains $decision.$key) { $failures += "INVALID_FIELD_$key" }
        }
        foreach ($key in $keys) { if ($allowed.Keys -cnotcontains $key) { $failures += "UNEXPECTED_KEY_$key" } }
        $schema=$failures.Count -eq 0
    }
    if ($schema) { $failures += @(Get-DecisionPolicyFailures $Candidate $decision $EvaluationMode) }
    if ($ExitCode -ne 0) { $failures += "LLAMA_EXIT_CODE_$ExitCode" }
    if ($TimedOut) { $failures += 'LLAMA_PROCESS_TIMEOUT' }
    $business=$schema -and $failures.Count -eq 0
    $reasonWarnings=@(if ($schema -and $EvaluationMode -eq 'INDEPENDENT') { Get-DecisionEvidenceWarnings $Candidate $decision })
    if ($schema) {
        if ($decision.decision -cne $Candidate.javaDecision) { $warnings += 'DECISION_DIVERGED_FROM_JAVA_GUARDRAIL' }
        if ($decision.riskBucket -cne $Candidate.javaRiskBucket) { $warnings += 'RISK_BUCKET_DIVERGED_FROM_JAVA_GUARDRAIL' }
        if ($decision.scoreBand -cne $Candidate.javaScoreBand) { $warnings += 'SCORE_BAND_DIVERGED_FROM_JAVA_GUARDRAIL' }
    }
    $warnings += $reasonWarnings
    $diagnosticFailures=@(Get-TypedDiagnosticFailures $Candidate $decision $business $reasonWarnings)
    $expected=@(if ($Candidate.PSObject.Properties['diagnosticExpectedDecisions']) { $Candidate.diagnosticExpectedDecisions | Where-Object { $_ } })
    [pscustomobject]@{
        extraction=$extraction; decision=$decision; parseableJson=$parseable; schemaValid=$schema; businessValid=$business
        failureStage=$(if ($extraction.error) { 'EXTRACTION' } elseif (-not $schema) { 'SCHEMA' }
            elseif ($ExitCode -ne 0 -or $TimedOut) { 'PROCESS' } elseif (-not $business) { 'POLICY' } else { 'NONE' })
        aligned=($business -and $decision.decision -ceq $Candidate.javaDecision -and $decision.riskBucket -ceq $Candidate.javaRiskBucket -and $decision.scoreBand -ceq $Candidate.javaScoreBand)
        failures=$failures; warnings=$warnings; reasonEvidenceWarnings=$reasonWarnings
        diagnosticExpectedDecisions=$expected; diagnosticFailures=$diagnosticFailures
        diagnosticPassed=$(if ($expected.Count) { $diagnosticFailures.Count -eq 0 } else { $null })
    }
}

function New-IndependentDecisionGrammar {
    param([object]$Candidate, [string]$Grammar)
    if ([string]$Candidate.candidateId -cnotmatch '^CANDIDATE_[0-9]{3}$') {
        throw 'Invalid candidate id for independent grammar.'
    }
    # Only identity is bound. No Java answer, score, risk or outcome controls the alternatives.
    $identityRule = 'candidate-id ::= "\"' + [string]$Candidate.candidateId + '\""'
    if ($Grammar -notmatch '(?m)^candidate-id ::=') { throw 'Missing candidate-id grammar rule.' }
    $result = [regex]::Replace($Grammar, '(?m)^candidate-id ::=[^\r\n]*', $identityRule)
    return $result.Replace(' | "\"JAVA_BASELINE_ALIGNED\""', '')
}

function Get-DecisionPolicyFailures {
    param([object]$Candidate, [object]$Decision, [string]$EvaluationMode)
    if ($Decision.riskBucket -ceq 'BLOCKED' -and $Decision.decision -cne 'REJECT') {
        'BLOCKED_REQUIRES_REJECT'
    }
    if ($Candidate.javaTopPickEligibility -ceq 'BLOCKED' -and $Decision.decision -ceq 'TOP_PICK') {
        'JAVA_BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK'
    }
    if ($Decision.decision -ceq 'REJECT' -and @('HIGH', 'VERY_HIGH') -ccontains $Decision.scoreBand) {
        'REJECT_WITH_HIGH_SCORE_BAND'
    }
    if ($Decision.riskBucket -ceq 'BLOCKED' -and @('MEDIUM', 'HIGH', 'VERY_HIGH') -ccontains $Decision.scoreBand) {
        'BLOCKED_WITH_ELEVATED_SCORE_BAND'
    }
    if ($Candidate.javaScoreCapHint -ceq 'HARD_CAP_54') {
        if (@('HIGH', 'VERY_HIGH') -ccontains $Decision.scoreBand) { 'HARD_CAP_54_SCORE_BAND_VIOLATION' }
        if ($Decision.decision -ceq 'TOP_PICK') { 'HARD_CAP_54_TOP_PICK_VIOLATION' }
    }
    if ($Candidate.javaScoreCapHint -ceq 'HARD_CAP_69') {
        if ($Decision.scoreBand -ceq 'VERY_HIGH') { 'HARD_CAP_69_SCORE_BAND_VIOLATION' }
        if ($Decision.decision -ceq 'TOP_PICK') { 'HARD_CAP_69_TOP_PICK_VIOLATION' }
    }
    if ($EvaluationMode -eq 'INDEPENDENT') {
        if ($Candidate.hardExclusionReason -cne 'NONE') {
            if ($Decision.decision -cne 'REJECT' -or $Decision.riskBucket -cne 'BLOCKED') {
                'HARD_EXCLUSION_NOT_RESPECTED'
            }
        }
        elseif ($Decision.riskBucket -ceq 'BLOCKED') {
            'BLOCKED_WITHOUT_HARD_EXCLUSION'
        }
        if ($Decision.primaryReasonCode -ceq 'JAVA_BASELINE_ALIGNED') { 'BASELINE_REASON_IN_INDEPENDENT_MODE' }
    }
}

function Get-DecisionEvidenceWarnings {
    param([object]$Candidate, [object]$Decision)
    if (-not $Candidate.PSObject.Properties['featureEvidence']) { return }
    $facts = $Candidate.featureEvidence
    if ($Decision.primaryReasonCode -ceq 'WEAK_TREND' -and
        $facts.priceVsAverages -ceq 'ABOVE_ALL' -and $facts.emaDirection -ceq 'POSITIVE') {
        'WEAK_TREND_CONTRADICTS_ALIGNED_TREND_FACTS'
    }
    if ($Decision.primaryReasonCode -ceq 'STRONG_MOMENTUM' -and
        $facts.priceVsAverages -ceq 'BELOW_ALL' -and $facts.emaDirection -ceq 'NEGATIVE') {
        'STRONG_MOMENTUM_CONTRADICTS_BEARISH_FACTS'
    }
    if ($Decision.primaryReasonCode -ceq 'BLOCKED_BY_RISK' -and $Candidate.hardExclusionReason -ceq 'NONE') {
        'BLOCKED_REASON_WITHOUT_HARD_EXCLUSION'
    }
    if ($Decision.primaryReasonCode -ceq 'RELATIVE_STRENGTH') { 'RELATIVE_STRENGTH_BENCHMARK_NOT_SUPPLIED' }
}

function Get-TypedDiagnosticFailures {
    param([object]$Candidate, [object]$Decision, [bool]$BusinessValid, [object[]]$ReasonWarnings)
    if (-not $Candidate.PSObject.Properties['diagnosticExpectedDecisions'] -or
        @($Candidate.diagnosticExpectedDecisions | Where-Object { $_ }).Count -eq 0) { return }
    if (-not $BusinessValid) { 'DIAGNOSTIC_INVALID_RESPONSE'; return }
    if (@($Candidate.diagnosticExpectedDecisions) -cnotcontains $Decision.decision) { 'DIAGNOSTIC_DECISION_MISMATCH' }
    if ($ReasonWarnings.Count -gt 0) { 'DIAGNOSTIC_UNSUPPORTED_REASON' }
    if ($Candidate.symbol -eq 'SYNTHETIC_HIGH_VOL' -and $Decision.riskBucket -cne 'HIGH') { 'DIAGNOSTIC_HIGH_VOL_RISK_MISSED' }
    if ($Candidate.symbol -eq 'SYNTHETIC_MISSING_VOLUME' -and $Decision.primaryReasonCode -cne 'BLOCKED_BY_RISK') {
        'DIAGNOSTIC_MISSING_INPUT_REASON_MISSED'
    }
}

function Get-TypedDecisionEvaluation {
    param([object[]]$Attempts)
    $valid = @($Attempts | Where-Object { $_.businessValid })
    $modelSelected = @($valid | Where-Object { $_.modelDecision -in @('SHORTLIST', 'TOP_PICK') })
    $javaSelected = @($Attempts | Where-Object { $_.javaDecision -in @('SHORTLIST', 'TOP_PICK') })
    $labelled = @($Attempts | Where-Object {
        $null -ne $_.targetNetReturnPercent -and $null -ne $_.targetBenchmarkExcessReturnPercent
    })
    $positive = @($labelled | Where-Object {
        $_.targetNetReturnPercent -gt 0 -and $_.targetBenchmarkExcessReturnPercent -gt 0
    })
    $modelHits = @($positive | Where-Object {
        $_.businessValid -and $_.modelDecision -in @('SHORTLIST', 'TOP_PICK')
    })
    $javaHits = @($positive | Where-Object { $_.javaDecision -in @('SHORTLIST', 'TOP_PICK') })
    $modelLabelled = @($modelSelected | Where-Object {
        $null -ne $_.targetNetReturnPercent -and $null -ne $_.targetBenchmarkExcessReturnPercent
    })
    $javaLabelled = @($javaSelected | Where-Object {
        $null -ne $_.targetNetReturnPercent -and $null -ne $_.targetBenchmarkExcessReturnPercent
    })
    $modelDrawdown = @($modelSelected | Where-Object { $null -ne $_.targetMaximumDrawdownPercent })
    $javaDrawdown = @($javaSelected | Where-Object { $null -ne $_.targetMaximumDrawdownPercent })
    $categories = @('OPPORTUNITY', 'CAUTION', 'AVOID')
    $coverage = @($categories | ForEach-Object {
        $category = $_
        [pscustomobject]@{ category = $category; count = @($Attempts | Where-Object { $_.evidenceCategory -eq $category }).Count }
    })
    $warnings = @()
    $diagnostic = @($Attempts | Where-Object {
        $_.PSObject.Properties['diagnosticExpectedDecisions'] -and @($_.diagnosticExpectedDecisions).Count -gt 0
    })
    $diagnosticPassed = @($diagnostic | Where-Object { $_.diagnosticPassed -eq $true })
    $reasonWarnings = @($Attempts | Where-Object {
        $_.PSObject.Properties['reasonEvidenceWarnings'] -and @($_.reasonEvidenceWarnings).Count -gt 0
    })
    if ($diagnostic.Count -gt 0) { $warnings += 'SYNTHETIC_POLICY_TEST_NOT_INVESTMENT_ACCURACY' }
    if ($diagnosticPassed.Count -lt $diagnostic.Count) { $warnings += 'CONTRAST_DIAGNOSTIC_FAILED' }
    if ($reasonWarnings.Count -gt 0) { $warnings += 'REASONS_REQUIRE_EVIDENCE_REVIEW' }
    if (@($coverage | Where-Object { $_.count -eq 0 }).Count -gt 0) { $warnings += 'INCOMPLETE_SCENARIO_COVERAGE' }
    if ($Attempts.Count -lt 30) { $warnings += 'SMALL_SAMPLE_NOT_GENERALIZATION_EVIDENCE' }
    if ($valid.Count -gt 0 -and @($valid | Where-Object { $_.modelDecision -ne 'REJECT' }).Count -eq 0) {
        $warnings += 'ALL_VALID_DECISIONS_REJECTED'
    }
    if ($labelled.Count -lt $Attempts.Count) { $warnings += 'INCOMPLETE_OUTCOME_LABELS' }
    [pscustomobject][ordered]@{
        metricVersion = 'INDEPENDENT_DECISION_EVALUATION_V3'
        diagnosticCaseCount = $diagnostic.Count
        diagnosticPassedCount = $diagnosticPassed.Count
        diagnosticPassPercent = if ($diagnostic.Count) { [math]::Round(100.0 * $diagnosticPassed.Count / $diagnostic.Count, 2) } else { $null }
        reasonEvidenceWarningCount = $reasonWarnings.Count
        rawDecisionDistribution = @($Attempts | Group-Object modelDecision | ForEach-Object {
            [pscustomobject]@{decision=$_.Name; count=$_.Count}
        })
        outcomeDefinition = 'Positive net return AND positive benchmark excess over the configured horizon; retrospective diagnostic, not a trading ground truth.'
        categoryCoverage = $coverage
        validModelDecisionCount = $valid.Count
        modelSelectedCount = $modelSelected.Count
        javaSelectedCount = $javaSelected.Count
        labelledCandidateCount = $labelled.Count
        positiveOutcomeCount = $positive.Count
        modelPositiveOutcomeRecallPercent = if ($positive.Count) { [math]::Round(100.0 * $modelHits.Count / $positive.Count, 2) } else { $null }
        javaPositiveOutcomeRecallPercent = if ($positive.Count) { [math]::Round(100.0 * $javaHits.Count / $positive.Count, 2) } else { $null }
        modelSelectedPositiveOutcomePercent = if ($modelLabelled.Count) { [math]::Round(100.0 * $modelHits.Count / $modelLabelled.Count, 2) } else { $null }
        javaSelectedPositiveOutcomePercent = if ($javaLabelled.Count) { [math]::Round(100.0 * $javaHits.Count / $javaLabelled.Count, 2) } else { $null }
        modelSelectedMeanNetReturnPercent = if ($modelLabelled.Count) { ($modelLabelled | Measure-Object targetNetReturnPercent -Average).Average } else { $null }
        javaSelectedMeanNetReturnPercent = if ($javaLabelled.Count) { ($javaLabelled | Measure-Object targetNetReturnPercent -Average).Average } else { $null }
        modelSelectedDrawdownLabelCount = $modelDrawdown.Count
        javaSelectedDrawdownLabelCount = $javaDrawdown.Count
        modelSelectedMeanMaximumDrawdownPercent = if ($modelDrawdown.Count) { ($modelDrawdown | Measure-Object targetMaximumDrawdownPercent -Average).Average } else { $null }
        javaSelectedMeanMaximumDrawdownPercent = if ($javaDrawdown.Count) { ($javaDrawdown | Measure-Object targetMaximumDrawdownPercent -Average).Average } else { $null }
        meanCandidateElapsedMillis = if ($Attempts.Count) { ($Attempts | Measure-Object elapsedMillis -Average).Average } else { $null }
        warnings = $warnings
        interpretation = 'Java alignment is agreement, not accuracy. Compare policies on identical candidates; stratified samples are not representative portfolio backtests. Unseen dates are still required.'
    }
}

function Save-TypedDecisionEvidence {
    [CmdletBinding()]
    param([object]$Evidence, [string]$Path, [switch]$KeepBackup)
    # Use a same-directory replacement, never delete the last good checkpoint first.
    # Unique temp names also avoid reusing a partial file left by an interrupted save.
    $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $temporaryPath = $destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Evidence | ConvertTo-Json -Depth 100))
    $stream = [IO.FileStream]::new($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    for ($saveAttempt = 1; $saveAttempt -le 6; $saveAttempt++) {
        try {
            if ([IO.File]::Exists($destination)) {
                $backupPath = if ($KeepBackup) { $destination + '.bak' } else { [NullString]::Value }
                [IO.File]::Replace($temporaryPath, $destination, $backupPath)
            } else {
                [IO.File]::Move($temporaryPath, $destination)
            }
            return
        } catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -isnot [IO.IOException] -or $saveAttempt -eq 6) {
                throw [IO.IOException]::new("Checkpoint save failed for '$destination' after $saveAttempt replacement attempt(s). Last checkpoint/backup were not deliberately deleted; pending evidence: '$temporaryPath'. $($cause.Message)", $cause)
            }
            Write-Warning "Checkpoint replacement retry $saveAttempt/6: $destination; $($cause.Message)"
            Start-Sleep -Milliseconds (200 * $saveAttempt)
        }
    }
}
