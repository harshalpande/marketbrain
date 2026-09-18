# Pure sweep planning, prompt transformation and ranking. No inference or HTTP calls here.
function ConvertFrom-SweepJson([string]$Json) {
    $options=@{InputObject=$Json}
    # PowerShell 7.5+ can coerce ISO timestamps into DateTime and change their textual representation on resume.
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind='String' }
    ConvertFrom-Json @options
}

function Get-SweepHash([object]$Value) {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 100 -Compress))
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function New-SweepConfigurations([string[]]$Layouts, [string[]]$ExampleModes, [double[]]$Temperatures, [int[]]$TokenLimits) {
    $seen=@{}; $number=0
    foreach ($layout in $Layouts) { foreach ($examples in $ExampleModes) {
        foreach ($temperature in $Temperatures) { foreach ($tokens in $TokenLimits) {
            $key="$layout|$examples|$($temperature.ToString([Globalization.CultureInfo]::InvariantCulture))|$tokens"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key]=$true; $number++
            [pscustomobject]@{id=('CONFIG_{0:D3}' -f $number); layout=$layout; examples=$examples; temperature=$temperature; maxTokens=$tokens}
        }}
    }}
}

function New-SweepPrompt([string]$Prompt, [object]$Configuration) {
    # Transform only the independent prompt. Never read Java answers, diagnostic expectations or future labels.
    $marker='Assess the following input, independently of any Java baseline:'
    $position=$Prompt.IndexOf($marker, [StringComparison]::Ordinal)
    if ($position -lt 0) { throw 'Unrecognized independent prompt layout; refusing a guessed transformation.' }
    $policy=$Prompt.Substring(0,$position).Trim()
    $facts=$Prompt.Substring($position).Trim()
    $result=if ($Configuration.layout -eq 'FACTS_FIRST') { "$facts`n`n$policy" } else { $Prompt }
    if ($Configuration.examples -eq 'CONSISTENCY') {
        # Format/policy examples, not feature-to-answer demonstrations of the screening cases.
        $result += "`nConsistency examples (not this candidate's answer): REJECT + HIGH score is invalid; REJECT + LOW score is consistent. WATCHLIST + HIGH risk + MEDIUM score is consistent. BLOCKED + SHORTLIST is invalid. Do not copy an example; use the candidate facts."
    }
    return $result
}

function Get-SweepLeaderboard([object]$Report) {
    $rows=@(foreach ($config in $Report.configurations) {
        $tasks=@($Report.tasks | Where-Object { $_.configurationId -eq $config.id })
        $records=@($Report.records | Where-Object { $_.configurationId -eq $config.id })
        $attempts=@($records | Where-Object { $null -ne $_.attempt } | ForEach-Object { $_.attempt })
        $schema=@($attempts | Where-Object { $_.schemaValid }).Count
        $business=@($attempts | Where-Object { $_.businessValid }).Count
        $passes=@($attempts | Where-Object { $_.diagnosticPassed -eq $true }).Count
        $unsafe=@($attempts | Where-Object {
            $_.modelDecision -in @('SHORTLIST','TOP_PICK') -and $_.hardExclusionReason -ne 'NONE'
        }).Count
        $reasonCount=0; foreach ($a in $attempts) { $reasonCount += @($a.reasonEvidenceWarnings).Count }
        $diagnosticCount=@($Report.snapshot.candidates | Where-Object {
            @($_.diagnosticExpectedDecisions | Where-Object { $_ }).Count -gt 0
        }).Count
        $complete=$records.Count -eq $tasks.Count
        $qualified=$complete -and @($records | Where-Object { $_.error }).Count -eq 0 -and $tasks.Count -gt 0 -and $diagnosticCount -eq $Report.snapshot.candidates.Count -and
            $passes -eq $tasks.Count -and $business -eq $tasks.Count -and $unsafe -eq 0 -and $reasonCount -eq 0
        $stable=0; $repeatCases=0
        foreach ($group in @($records | Group-Object caseIndex)) {
            if ($group.Count -ne $Report.settings.repeats) { continue }
            $signatures=@($group.Group | ForEach-Object {
                if ($null -eq $_.attempt -or -not $_.attempt.schemaValid) { "INVALID_$($_.taskId)" }
                else { @($_.attempt.modelDecision,$_.attempt.modelRiskBucket,$_.attempt.modelTrapDetected,$_.attempt.modelScoreBand,$_.attempt.modelConfidenceBand,$_.attempt.modelPrimaryReasonCode) -join '|' }
            } | Select-Object -Unique)
            $repeatCases++; if ($signatures.Count -eq 1) { $stable++ }
        }
        $denominator=[math]::Max(1,$records.Count)
        $times=@($attempts | ForEach-Object { [double]$_.elapsedMillis/1000 } | Sort-Object)
        [pscustomobject]@{
            configurationId=$config.id; configuration=$config; complete=$complete; qualifiesForNextStage=$qualified
            planned=$tasks.Count; completed=$records.Count; errors=@($records | Where-Object { $_.error }).Count
            schemaValidPercent=[math]::Round(100.0*$schema/$denominator,2)
            businessValidPercent=[math]::Round(100.0*$business/$denominator,2)
            diagnosticPassPercent=$(if ($diagnosticCount -gt 0) { [math]::Round(100.0*$passes/$denominator,2) } else { $null })
            unsafePromotionCount=$unsafe; reasonWarningCount=$reasonCount
            repeatConsistencyPercent=$(if ($repeatCases -gt 0 -and $Report.settings.repeats -gt 1) { [math]::Round(100.0*$stable/$repeatCases,2) } else { $null })
            meanAttemptSeconds=$(if ($attempts.Count) { [math]::Round(($attempts | Measure-Object elapsedMillis -Average).Average/1000,2) } else { $null })
            p95AttemptSeconds=$(if ($times.Count) { [math]::Round($times[[math]::Ceiling(0.95*$times.Count)-1],2) } else { $null })
            failureCounts=@($attempts | ForEach-Object { if ($_.PSObject.Properties['failures']) { $_.failures } } | Group-Object | ForEach-Object { [pscustomobject]@{code=$_.Name;count=$_.Count} })
            totalTaskSeconds=$(if ($records.Count) { [math]::Round(($records | Measure-Object elapsedSeconds -Sum).Sum,2) } else { 0 })
            outcomeEvaluation=$(if ($attempts.Count -gt 0 -and $attempts[0].PSObject.Properties['targetNetReturnPercent']) { Get-TypedDecisionEvaluation $attempts } else { $null })
            decisionDistribution=@($attempts | Group-Object modelDecision | ForEach-Object { [pscustomobject]@{decision=$_.Name; count=$_.Count} })
        }
    })
    # Gates precede speed. Incomplete/failed cases remain in denominators, never disappear from ranking.
    $rows | Sort-Object @{Expression='qualifiesForNextStage';Descending=$true}, @{Expression='complete';Descending=$true},
        unsafePromotionCount, @{Expression='diagnosticPassPercent';Descending=$true},
        @{Expression='businessValidPercent';Descending=$true}, reasonWarningCount,
        @{Expression='repeatConsistencyPercent';Descending=$true}, meanAttemptSeconds, configurationId
}

function Invoke-SweepCandidate([hashtable]$Parameters) {
    & (Join-Path $PSScriptRoot 'PreviewPrototypeSwingTypedDecisionPrimitives.ps1') @Parameters | Out-Host
}

function Get-SweepSnapshot([string]$BaseUrl, [string]$DatasetRunId, [string]$SelectionMode, [int]$StartOffset, [int]$CandidateLimit, [int]$Horizon) {
    $body=@{datasetRunId=$DatasetRunId;selectionMode=$SelectionMode;startOffset=$StartOffset;candidateLimit=$CandidateLimit;rankingHorizonSessions=$Horizon}
    # This preview endpoint is review-only; the frozen response is reused for every configuration/repetition.
    Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/training/prototype-swing-typed-decision-primitives" -ContentType 'application/json' -Body ($body | ConvertTo-Json) -TimeoutSec 180
}
