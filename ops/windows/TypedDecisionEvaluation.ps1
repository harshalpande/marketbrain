# Pure evaluation helpers. Importing this file does not contact services or run a model.
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
    $categories = @('OPPORTUNITY', 'CAUTION', 'AVOID')
    $coverage = @($categories | ForEach-Object {
        $category = $_
        [pscustomobject]@{ category = $category; count = @($Attempts | Where-Object { $_.evidenceCategory -eq $category }).Count }
    })
    $warnings = @()
    if (@($coverage | Where-Object { $_.count -eq 0 }).Count -gt 0) { $warnings += 'INCOMPLETE_SCENARIO_COVERAGE' }
    if ($Attempts.Count -lt 30) { $warnings += 'SMALL_SAMPLE_NOT_GENERALIZATION_EVIDENCE' }
    if ($valid.Count -gt 0 -and @($valid | Where-Object { $_.modelDecision -ne 'REJECT' }).Count -eq 0) {
        $warnings += 'ALL_VALID_DECISIONS_REJECTED'
    }
    if ($labelled.Count -lt $Attempts.Count) { $warnings += 'INCOMPLETE_OUTCOME_LABELS' }
    [pscustomobject][ordered]@{
        metricVersion = 'INDEPENDENT_DECISION_EVALUATION_V1'
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
        modelSelectedMeanMaximumDrawdownPercent = if ($modelSelected.Count) { ($modelSelected | Measure-Object targetMaximumDrawdownPercent -Average).Average } else { $null }
        javaSelectedMeanMaximumDrawdownPercent = if ($javaSelected.Count) { ($javaSelected | Measure-Object targetMaximumDrawdownPercent -Average).Average } else { $null }
        meanCandidateElapsedMillis = if ($Attempts.Count) { ($Attempts | Measure-Object elapsedMillis -Average).Average } else { $null }
        warnings = $warnings
        interpretation = 'Java alignment is agreement, not accuracy. Compare policies on identical candidates; stratified samples are not representative portfolio backtests. Unseen dates are still required.'
    }
}

function Save-TypedDecisionEvidence {
    param([object]$Evidence, [string]$Path)
    $temporaryPath = $Path + '.tmp'
    $Evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}
