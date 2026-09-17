[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'ibm/granite4.1:8b',

    [Parameter()]
    [ValidateSet('FIXED_SYMBOL', 'RANDOM_VALIDATION', 'DIFFICULT_TRAPS', 'RECOVERY_OVEREXTENSION')]
    [string[]]$SelectionModes = @('FIXED_SYMBOL', 'RANDOM_VALIDATION', 'DIFFICULT_TRAPS'),

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$TotalCandidateLimitPerScenario = 12,

    [Parameter()]
    [ValidateRange(0, 500)]
    [int]$StartOffset = 0,

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$ChunkSize = 4,

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$FinalistsPerChunk = 2,

    [Parameter()]
    [ValidateRange(0, 3)]
    [int]$MaxRetriesPerChunk = 1,

    [Parameter()]
    [ValidateSet(5, 20, 60)]
    [int]$RankingHorizonSessions = 20,

    [Parameter()]
    [ValidateRange(10, 300)]
    [int]$StatusPollTimeoutSeconds = 180,

    [Parameter()]
    [ValidateRange(60, 43200)]
    [int]$TimeoutSecondsPerScenario = 21600,

    [Parameter()]
    [bool]$ResumeCompletedScenarios = $true,

    [Parameter()]
    [ValidateRange(1, 60)]
    [int]$HealthRetrySeconds = 10,

    [Parameter()]
    [ValidateRange(1, 60)]
    [int]$HealthRetryCount = 18,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-StepProgress {
    param(
        [int]$Percent,
        [string]$Message
    )
    Write-Progress -Activity 'Step 87 Granite multi-scenario validation' -Status $Message -PercentComplete $Percent
    Write-Host ("[{0}%] {1}" -f $Percent, $Message)
}

function Safe-Name {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9._-]', '_')
}

function Wait-MarketBrainHealth {
    for ($attempt = 1; $attempt -le $HealthRetryCount; $attempt++) {
        try {
            $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 30
            if ($health.status -eq 'UP') {
                Write-Host "MarketBrain health is UP on attempt $attempt/$HealthRetryCount."
                return
            }
            Write-Host "MarketBrain health is $($health.status) on attempt $attempt/$HealthRetryCount; waiting $HealthRetrySeconds seconds..."
        }
        catch {
            Write-Host "MarketBrain health check failed on attempt $attempt/${HealthRetryCount}: $($_.Exception.Message)"
        }
        if ($attempt -lt $HealthRetryCount) {
            Start-Sleep -Seconds $HealthRetrySeconds
        }
    }
    throw "MarketBrain service did not become healthy after $HealthRetryCount attempts."
}

function Latest-File {
    param([string]$Pattern)
    $file = Get-ChildItem -Path $OutputDirectory -Filter $Pattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $file) {
        throw "No file found for pattern $Pattern in $OutputDirectory"
    }
    return $file.FullName
}

function Scenario-Stem {
    param([string]$Mode)
    return "prototype-swing-ollama-chunked-ranking-async-$DatasetRunId-$safeModel-$(Safe-Name $Mode)-h$RankingHorizonSessions-offset$StartOffset-total$TotalCandidateLimitPerScenario-chunk$ChunkSize"
}

function Latest-Scorecard-Or-Null {
    param([string]$ScenarioStem)
    $file = Get-ChildItem -Path $OutputDirectory -Filter "$ScenarioStem-intelligence-scorecard-*.json" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $file) {
        return $null
    }
    return $file.FullName
}

function Test-CompletedScenarioResult {
    param([string]$ResultPath)
    if (-not (Test-Path -LiteralPath $ResultPath)) {
        return $false
    }
    try {
        $json = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
        if (($json.PSObject.Properties.Name -contains 'status') -and $json.status -eq 'COMPLETED') {
            return $true
        }
        if (($json.PSObject.Properties.Name -contains 'result') -and $null -ne $json.result) {
            return $true
        }
        return $false
    }
    catch {
        Write-Warning "Existing scenario result is not readable and will not be reused: $ResultPath :: $($_.Exception.Message)"
        return $false
    }
}

function Scenario-Result {
    param(
        [int]$ScenarioNumber,
        [string]$Mode,
        [string]$ScenarioStatus,
        [string]$ScenarioSource,
        [string]$ScenarioError,
        [string]$ResultPath,
        [string]$ScorecardPath,
        [object]$Scorecard
    )
    return [pscustomobject][ordered]@{
        scenarioNumber                    = $ScenarioNumber
        selectionMode                     = $Mode
        status                            = $ScenarioStatus
        source                            = $ScenarioSource
        errorMessage                      = $ScenarioError
        resultPath                        = $ResultPath
        scorecardPath                     = $ScorecardPath
        overallIntelligenceScorePercent  = if ($null -eq $Scorecard) { $null } else { $Scorecard.overallIntelligenceScorePercent }
        pendingImprovementPercent        = if ($null -eq $Scorecard) { $null } else { $Scorecard.pendingImprovementPercent }
        maturityBand                     = if ($null -eq $Scorecard) { $null } else { $Scorecard.maturityBand }
        pipelineReliabilityPercent       = if ($null -eq $Scorecard) { $null } else { $Scorecard.pipelineReliabilityPercent }
        schemaDisciplinePercent          = if ($null -eq $Scorecard) { $null } else { $Scorecard.schemaDisciplinePercent }
        scoreCalibrationPercent          = if ($null -eq $Scorecard) { $null } else { $Scorecard.scoreCalibrationPercent }
        rankingQualityPercent            = if ($null -eq $Scorecard) { $null } else { $Scorecard.rankingQualityPercent }
        finalistQualityPercent           = if ($null -eq $Scorecard) { $null } else { $Scorecard.finalistQualityPercent }
        failedChunkCount                 = if ($null -eq $Scorecard) { $null } else { $Scorecard.failedChunkCount }
        warningChunkCount                = if ($null -eq $Scorecard) { $null } else { $Scorecard.warningChunkCount }
        passedChunkCount                 = if ($null -eq $Scorecard) { $null } else { $Scorecard.passedChunkCount }
        negativeReturnTopPickCount       = if ($null -eq $Scorecard) { $null } else { $Scorecard.negativeReturnTopPickCount }
        weakTopPickCount                 = if ($null -eq $Scorecard) { $null } else { $Scorecard.weakTopPickCount }
        topImprovementActions            = if ($null -eq $Scorecard) { @() } else { @($Scorecard.topImprovementActions) }
    }
}

function Build-Aggregate {
    param([object[]]$ScenarioResultRows)
    $completed = @($ScenarioResultRows | Where-Object { $_.status -eq 'COMPLETED' })
    $failed = @($ScenarioResultRows | Where-Object { $_.status -ne 'COMPLETED' })
    $actionCounts = @{}
    foreach ($scenario in $completed) {
        foreach ($action in @($scenario.topImprovementActions)) {
            if (-not $actionCounts.ContainsKey($action)) {
                $actionCounts[$action] = 0
            }
            $actionCounts[$action]++
        }
    }
    $rankedActions = $actionCounts.GetEnumerator() |
        Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true } |
        ForEach-Object {
            [pscustomobject][ordered]@{
                action = $_.Key
                scenarioCount = $_.Value
            }
        }

    $overallScores = @($completed | Where-Object { $null -ne $_.overallIntelligenceScorePercent } | ForEach-Object { [int]$_.overallIntelligenceScorePercent })
    return [pscustomobject][ordered]@{
        status                              = if ($failed.Count -gt 0) { 'REVIEW_WITH_FAILURES' } elseif ($completed.Count -lt $SelectionModes.Count) { 'PARTIAL_CHECKPOINT' } elseif (($overallScores | Where-Object { $_ -lt 85 }).Count -gt 0) { 'REVIEW_WITH_WARNINGS' } else { 'READY_FOR_NEXT_TRAINING_ITERATION' }
        checkpointWrittenAt                 = (Get-Date).ToString('o')
        datasetRunId                        = $DatasetRunId
        model                               = $Model
        rankingHorizonSessions              = $RankingHorizonSessions
        scenarioCount                       = $SelectionModes.Count
        completedScenarioCount              = $completed.Count
        failedScenarioCount                 = $failed.Count
        totalCandidateLimitPerScenario      = $TotalCandidateLimitPerScenario
        chunkSize                           = $ChunkSize
        averageOverallIntelligencePercent   = if ($overallScores.Count -eq 0) { $null } else { [int][Math]::Round(($overallScores | Measure-Object -Average).Average) }
        minimumOverallIntelligencePercent   = if ($overallScores.Count -eq 0) { $null } else { ($overallScores | Measure-Object -Minimum).Minimum }
        maximumPendingImprovementPercent    = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.pendingImprovementPercent }) | Measure-Object -Maximum).Maximum }
        minimumPipelineReliabilityPercent   = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.pipelineReliabilityPercent }) | Measure-Object -Minimum).Minimum }
        minimumSchemaDisciplinePercent      = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.schemaDisciplinePercent }) | Measure-Object -Minimum).Minimum }
        minimumScoreCalibrationPercent      = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.scoreCalibrationPercent }) | Measure-Object -Minimum).Minimum }
        minimumRankingQualityPercent        = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.rankingQualityPercent }) | Measure-Object -Minimum).Minimum }
        minimumFinalistQualityPercent       = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.finalistQualityPercent }) | Measure-Object -Minimum).Minimum }
        totalFailedChunks                   = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.failedChunkCount }) | Measure-Object -Sum).Sum }
        totalWarningChunks                  = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.warningChunkCount }) | Measure-Object -Sum).Sum }
        totalNegativeReturnTopPickCount     = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.negativeReturnTopPickCount }) | Measure-Object -Sum).Sum }
        totalWeakTopPickCount               = if ($completed.Count -eq 0) { $null } else { (@($completed | ForEach-Object { [int]$_.weakTopPickCount }) | Measure-Object -Sum).Sum }
        scenarioResults                     = @($ScenarioResultRows)
        recurringImprovementActions         = @($rankedActions)
        guardrails                          = @(
            'Review-only validation. No signal, paper fill, broker order, or live trading action is created.',
            'Scenario selection uses as-of features only; hidden future labels remain evaluator-only.',
            'Local Ollama/Granite model concurrency remains 1; scenarios are run sequentially.',
            'Partial checkpoint is written after every scenario so completed work can be reused after shutdown.'
        )
    }
}

function Save-AggregateCheckpoint {
    param([object[]]$ScenarioResultRows)
    $aggregate = Build-Aggregate -ScenarioResultRows $ScenarioResultRows
    $aggregate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8
    Write-Host "Step 87 checkpoint written: $aggregatePath"
    return $aggregate
}

if ($SelectionModes.Count -lt 2) {
    throw 'Step 87 should validate at least two selection modes.'
}
if ($FinalistsPerChunk -gt $ChunkSize) {
    throw 'FinalistsPerChunk cannot be greater than ChunkSize.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$safeModel = Safe-Name $Model
$scenarioSlug = ($SelectionModes | ForEach-Object { Safe-Name $_ }) -join '-'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$aggregateStem = "prototype-swing-ollama-multi-scenario-validation-$DatasetRunId-$safeModel-h$RankingHorizonSessions-total$TotalCandidateLimitPerScenario-scenarios-$scenarioSlug-$timestamp"
$aggregatePath = Join-Path $OutputDirectory "$aggregateStem.json"
$aggregateLogPath = Join-Path $OutputDirectory "$aggregateStem.log"

$transcriptStarted = $false
$scenarioResults = New-Object System.Collections.Generic.List[object]

try {
    Start-Transcript -Path $aggregateLogPath -Force | Out-Null
    $transcriptStarted = $true

    Write-StepProgress 0 'Validating MarketBrain service health...'
    Wait-MarketBrainHealth

    $rankingScript = (Resolve-Path '.\ops\windows\PreviewPrototypeSwingOllamaChunkedRankingAsync.ps1').Path
    $scorecardScript = (Resolve-Path '.\ops\windows\ReviewPrototypeSwingOllamaIntelligenceScorecard.ps1').Path
    $pwshPath = (Get-Process -Id $PID).Path

    Write-Host 'Step 87: running Granite multi-scenario validation.'
    Write-Host "Scenarios: $($SelectionModes -join ', ')"
    Write-Host "Candidates per scenario: $TotalCandidateLimitPerScenario; chunk size: $ChunkSize"
    Write-Host "Resume completed scenarios: $ResumeCompletedScenarios"
    Write-Host 'Each scenario remains review-only: no database write, signal, paper fill, order, broker action, or live trading action will be created.'
    Save-AggregateCheckpoint -ScenarioResultRows @($scenarioResults) | Out-Null

    for ($index = 0; $index -lt $SelectionModes.Count; $index++) {
        $mode = $SelectionModes[$index]
        $scenarioNumber = $index + 1
        $basePercent = [int][Math]::Floor(($index / [double]$SelectionModes.Count) * 100)
        Write-StepProgress $basePercent ("Starting scenario {0}/{1}: {2}" -f $scenarioNumber, $SelectionModes.Count, $mode)

        $scenarioStatus = 'UNKNOWN'
        $scenarioError = $null
        $resultPath = $null
        $scorecardPath = $null
        $scorecard = $null
        $scenarioSource = 'RAN_NOW'

        try {
            $scenarioStem = Scenario-Stem -Mode $mode
            $resultPath = Join-Path $OutputDirectory "$scenarioStem.json"
            $scorecardPath = Latest-Scorecard-Or-Null -ScenarioStem $scenarioStem

            if ($ResumeCompletedScenarios -and (Test-CompletedScenarioResult -ResultPath $resultPath)) {
                if ($null -ne $scorecardPath) {
                    Write-Host "Reusing completed scenario $mode from existing result and scorecard."
                    $scorecard = Get-Content -LiteralPath $scorecardPath -Raw | ConvertFrom-Json
                    $scenarioStatus = 'COMPLETED'
                    $scenarioSource = 'REUSED_EXISTING_RESULT_AND_SCORECARD'
                }
                else {
                    Write-Host "Scenario $mode already has result JSON; generating missing scorecard only."
                    $scenarioSource = 'REUSED_EXISTING_RESULT_GENERATED_SCORECARD'
                }
            }

            if ($scenarioStatus -ne 'COMPLETED') {
                if (-not ($ResumeCompletedScenarios -and (Test-CompletedScenarioResult -ResultPath $resultPath))) {
                    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $rankingScript `
                        -DatasetRunId $DatasetRunId `
                        -Model $Model `
                        -SelectionMode $mode `
                        -StartOffset $StartOffset `
                        -TotalCandidateLimit $TotalCandidateLimitPerScenario `
                        -ChunkSize $ChunkSize `
                        -FinalistsPerChunk $FinalistsPerChunk `
                        -MaxRetriesPerChunk $MaxRetriesPerChunk `
                        -RankingHorizonSessions $RankingHorizonSessions `
                        -StatusPollTimeoutSeconds $StatusPollTimeoutSeconds `
                        -TimeoutSeconds $TimeoutSecondsPerScenario `
                        -BaseUrl $BaseUrl `
                        -OutputDirectory $OutputDirectory
                    if ($LASTEXITCODE -ne 0) {
                        throw "Scenario $mode Step 70 child process failed with exit code $LASTEXITCODE."
                    }
                    if (-not (Test-Path -LiteralPath $resultPath)) {
                        throw "Scenario result file was not found: $resultPath"
                    }
                }

                & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $scorecardScript `
                    -ResultPath $resultPath `
                    -BaseUrl $BaseUrl `
                    -OutputDirectory $OutputDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "Scenario $mode scorecard child process failed with exit code $LASTEXITCODE."
                }

                $scorecardPath = Latest-File "$scenarioStem-intelligence-scorecard-*.json"
                $scorecard = Get-Content -LiteralPath $scorecardPath -Raw | ConvertFrom-Json
                $scenarioStatus = 'COMPLETED'
            }
        }
        catch {
            $scenarioStatus = 'FAILED'
            $scenarioError = $_.Exception.Message
            Write-Warning "Scenario $mode failed safely: $scenarioError"
        }

        $scenarioResults.Add((Scenario-Result `
                    -ScenarioNumber $scenarioNumber `
                    -Mode $mode `
                    -ScenarioStatus $scenarioStatus `
                    -ScenarioSource $scenarioSource `
                    -ScenarioError $scenarioError `
                    -ResultPath $resultPath `
                    -ScorecardPath $scorecardPath `
                    -Scorecard $scorecard))

        $donePercent = [int][Math]::Floor((($index + 1) / [double]$SelectionModes.Count) * 100)
        Write-StepProgress $donePercent ("Completed scenario {0}/{1}: {2} => {3}" -f $scenarioNumber, $SelectionModes.Count, $mode, $scenarioStatus)
        Save-AggregateCheckpoint -ScenarioResultRows @($scenarioResults) | Out-Null
    }

    $aggregate = Save-AggregateCheckpoint -ScenarioResultRows @($scenarioResults)

    Write-Host ''
    Write-Host 'Step 87 scenario summary'
    $scenarioResults |
        Select-Object selectionMode, status, source, overallIntelligenceScorePercent, pendingImprovementPercent,
            pipelineReliabilityPercent, scoreCalibrationPercent, rankingQualityPercent,
            finalistQualityPercent, failedChunkCount, warningChunkCount, negativeReturnTopPickCount,
            weakTopPickCount |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Recurring improvement actions'
    $aggregate.recurringImprovementActions | Format-Table -AutoSize

    Write-Host ''
    Write-Host 'STEP 87 COMPLETE: Granite multi-scenario validation finished.'
    Write-Host "Aggregate report: $aggregatePath"
    Write-Host "Aggregate log: $aggregateLogPath"
}
finally {
    Write-Progress -Activity 'Step 87 Granite multi-scenario validation' -Completed
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
