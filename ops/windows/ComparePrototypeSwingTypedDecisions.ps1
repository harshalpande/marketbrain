#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DatasetRunId,
    # Legacy multi-model comparison remains opt-in through explicit ModelRefs.
    [string[]]$ModelRefs = @('Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M'),
    [ValidateSet('BALANCED_VALIDATION', 'RECOVERY_OVEREXTENSION', 'RANDOM_VALIDATION', 'DIFFICULT_TRAPS', 'FIXED_SYMBOL')]
    [string]$SelectionMode = 'BALANCED_VALIDATION',
    [switch]$IncludeContrastChecks,
    [ValidateRange(3,24)][int]$CandidateLimit = 6,
    [ValidateSet(5,20,60)][int]$RankingHorizonSessions = 20,
    [string]$LlamaCliPath = 'C:\MarketBrainTools\llama.cpp\llama-cli.exe',
    [ValidateRange(10,300)][int]$TimeoutSeconds = 300,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
if ($ModelRefs.Count -lt 1 -or $ModelRefs.Count -gt 3) { throw 'Specify between one and three models.' }
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$runDirectory = Join-Path $OutputDirectory "typed-comparison-$stamp"
$workDirectory = Join-Path $runDirectory '_work'
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
$resultPath = Join-Path $runDirectory 'comparison.json'
$logPath = Join-Path $runDirectory 'comparison.log'
$report = [pscustomobject][ordered]@{
    status = 'RUNNING'; datasetRunId = $DatasetRunId; selectionMode = $SelectionMode
    evaluationMode = 'INDEPENDENT'; candidateLimit = $CandidateLimit
    rankingHorizonSessions = $RankingHorizonSessions; modelConcurrency = 1
    comparableInputs = $null; results = @(); comparison = @(); failures = @()
    comparedRunPairCount = 0; plannedStageCount = 0; completedStageCount = 0; skippedStageCount = 0
    contrastGateBlocked = $false
    actionExecutionEnabled = $false
}
function Write-ComparisonStatus([int]$Percent, [string]$Message) {
    Write-Progress -Id 89 -Activity 'Independent model comparison' -Status $Message -PercentComplete $Percent
    $line = '[{0}%] {1} {2}' -f $Percent, (Get-Date -Format o), $Message
    Write-Host $line
    [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}
$clock = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Save-TypedDecisionEvidence $report $resultPath
    $tasks = @(
        if ($IncludeContrastChecks) {
            foreach ($model in $ModelRefs) { [pscustomobject]@{ model=$model; mode='CONTRAST_VALIDATION'; limit=4 } }
        }
        foreach ($model in $ModelRefs) { [pscustomobject]@{ model=$model; mode=$SelectionMode; limit=$CandidateLimit } }
    )
    $report.plannedStageCount=$tasks.Count
    for ($index = 0; $index -lt $tasks.Count; $index++) {
        $task = $tasks[$index]
        $percent = [int][math]::Floor(100.0 * $index / $tasks.Count)
        Write-ComparisonStatus $percent "Starting stage $($index + 1)/$($tasks.Count): $($task.mode), $($task.model)"
        $childDirectory = Join-Path $workDirectory "model-$index"
        $parameters = @{
            DatasetRunId=$DatasetRunId; ModelRef=$task.model; SelectionMode=$task.mode
            EvaluationMode='INDEPENDENT'; StartOffset=0; CandidateLimit=$task.limit
            RankingHorizonSessions=$RankingHorizonSessions; LlamaCliPath=$LlamaCliPath
            TimeoutSeconds=$TimeoutSeconds; OutputDirectory=$childDirectory
        }
        $childError = $null
        try { & (Join-Path $PSScriptRoot 'PreviewPrototypeSwingTypedDecisionPrimitives.ps1') @parameters }
        catch { $childError = $_.Exception.Message }
        $jsonFile = Get-ChildItem -LiteralPath $childDirectory -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $jsonFile) { throw "No child evidence saved for $($task.model): $childError" }
        $childResult = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
        $report.results += $childResult
        $report.completedStageCount=$report.results.Count
        Get-ChildItem -LiteralPath $childDirectory -Filter '*.log' | ForEach-Object {
            [System.IO.File]::AppendAllText($logPath, [System.IO.File]::ReadAllText($_.FullName), [System.Text.Encoding]::UTF8)
        }
        Save-TypedDecisionEvidence $report $resultPath
        if ($null -ne $childError) { throw $childError }
        if ($task.mode -eq 'CONTRAST_VALIDATION' -and
            ($childResult.evaluation.diagnosticCaseCount -ne 4 -or $childResult.evaluation.diagnosticPassedCount -ne 4)) {
            $report.contrastGateBlocked = $true
            $report.skippedStageCount=$tasks.Count-$report.completedStageCount
            Write-ComparisonStatus ([int][Math]::Floor(100.0*($index+1)/$tasks.Count)) 'Diagnostic gate failed; remaining inference skipped. Review saved evidence before another run.'
            break
        }
    }
    $references = @{}
    $report.comparableInputs = $true
    foreach ($result in $report.results) {
        $signature = @($result.attempts | ForEach-Object {
            [ordered]@{ symbol=$_.symbol; prompt=$_.prompt; grammar=$_.grammar; netReturn=$_.targetNetReturnPercent; benchmarkExcess=$_.targetBenchmarkExcessReturnPercent; drawdown=$_.targetMaximumDrawdownPercent }
        }) | ConvertTo-Json -Depth 8 -Compress
        if ($references.ContainsKey($result.selectionMode)) {
            $report.comparedRunPairCount++
            if ($signature -cne $references[$result.selectionMode]) { $report.comparableInputs = $false }
        } else { $references[$result.selectionMode] = $signature }
        $report.comparison += [pscustomobject]@{
            model=$result.modelRef; scenario=$result.selectionMode; candidates=$result.candidateCount
            schemaValidPercent=$result.schemaValidPercent; businessValidPercent=$result.businessValidPercent
            javaAlignmentPercent=$result.javaAlignmentPercent; selected=$result.evaluation.modelSelectedCount
            positiveOutcomeRecallPercent=$result.evaluation.modelPositiveOutcomeRecallPercent
            diagnosticPassPercent=$result.evaluation.diagnosticPassPercent
            reasonEvidenceWarningCount=$result.evaluation.reasonEvidenceWarningCount
            averageSeconds=[math]::Round($result.evaluation.meanCandidateElapsedMillis / 1000.0, 2)
        }
    }
    if ($report.comparedRunPairCount -eq 0) { $report.comparableInputs=$null }
    $report.status = if ($report.contrastGateBlocked) { 'DIAGNOSTIC_GATE_BLOCKED' }
        elseif ($report.comparableInputs -eq $false) { 'INCOMPARABLE_INPUTS' }
        elseif (@($report.results | Where-Object { $_.status -ne 'REVIEW_REQUIRED' }).Count -gt 0) { 'REVIEW_WITH_WARNINGS' }
        else { 'REVIEW_REQUIRED' }
    Save-TypedDecisionEvidence $report $resultPath
    # All child JSON and logs have been embedded/appended and saved before removing temporary copies.
    $resolvedWork = (Resolve-Path -LiteralPath $workDirectory).Path
    $expectedParent = (Resolve-Path -LiteralPath $runDirectory).Path
    if ((Split-Path -Parent $resolvedWork) -eq $expectedParent -and (Split-Path -Leaf $resolvedWork) -eq '_work') {
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
    Write-ComparisonStatus 100 ("Comparison complete in {0:N1}s. Temporary child copies consolidated into comparison.json and comparison.log." -f $clock.Elapsed.TotalSeconds)
    $report.comparison | Format-Table -AutoSize
}
catch {
    $report.status = 'FAILED'
    $report.failures += [pscustomobject]@{ message=$_.Exception.Message; stack=$_.ScriptStackTrace }
    Save-TypedDecisionEvidence $report $resultPath
    Write-ComparisonStatus 100 "Comparison stopped: $($_.Exception.Message). Partial evidence preserved."
    throw
}
finally {
    Write-Progress -Id 89 -Activity 'Independent model comparison' -Completed
    Write-Host "Share: $resultPath"
    Write-Host "Share: $logPath"
}
