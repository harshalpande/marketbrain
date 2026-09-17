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
    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 30
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $rankingScript = (Resolve-Path '.\ops\windows\PreviewPrototypeSwingOllamaChunkedRankingAsync.ps1').Path
    $scorecardScript = (Resolve-Path '.\ops\windows\ReviewPrototypeSwingOllamaIntelligenceScorecard.ps1').Path
    $pwshPath = (Get-Process -Id $PID).Path

    Write-Host 'Step 87: running Granite multi-scenario validation.'
    Write-Host "Scenarios: $($SelectionModes -join ', ')"
    Write-Host "Candidates per scenario: $TotalCandidateLimitPerScenario; chunk size: $ChunkSize"
    Write-Host 'Each scenario remains review-only: no database write, signal, paper fill, order, broker action, or live trading action will be created.'

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

        try {
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

            $scenarioStem = "prototype-swing-ollama-chunked-ranking-async-$DatasetRunId-$safeModel-$(Safe-Name $mode)-h$RankingHorizonSessions-offset$StartOffset-total$TotalCandidateLimitPerScenario-chunk$ChunkSize"
            $resultPath = Join-Path $OutputDirectory "$scenarioStem.json"
            if (-not (Test-Path -LiteralPath $resultPath)) {
                throw "Scenario result file was not found: $resultPath"
            }

            & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $scorecardScript `
                -ResultPath $resultPath `
                -BaseUrl $BaseUrl `
                -OutputDirectory $OutputDirectory
            if ($LASTEXITCODE -ne 0) {
                throw "Scenario $mode scorecard child process failed with exit code $LASTEXITCODE."
            }

            $scorecardPattern = "$scenarioStem-intelligence-scorecard-*.json"
            $scorecardPath = Latest-File $scorecardPattern
            $scorecard = Get-Content -LiteralPath $scorecardPath -Raw | ConvertFrom-Json
            $scenarioStatus = 'COMPLETED'
        }
        catch {
            $scenarioStatus = 'FAILED'
            $scenarioError = $_.Exception.Message
            Write-Warning "Scenario $mode failed safely: $scenarioError"
        }

        $scenarioResults.Add([pscustomobject][ordered]@{
            scenarioNumber                    = $scenarioNumber
            selectionMode                     = $mode
            status                            = $scenarioStatus
            errorMessage                      = $scenarioError
            resultPath                        = $resultPath
            scorecardPath                     = $scorecardPath
            overallIntelligenceScorePercent  = if ($null -eq $scorecard) { $null } else { $scorecard.overallIntelligenceScorePercent }
            pendingImprovementPercent        = if ($null -eq $scorecard) { $null } else { $scorecard.pendingImprovementPercent }
            maturityBand                     = if ($null -eq $scorecard) { $null } else { $scorecard.maturityBand }
            pipelineReliabilityPercent       = if ($null -eq $scorecard) { $null } else { $scorecard.pipelineReliabilityPercent }
            schemaDisciplinePercent          = if ($null -eq $scorecard) { $null } else { $scorecard.schemaDisciplinePercent }
            scoreCalibrationPercent          = if ($null -eq $scorecard) { $null } else { $scorecard.scoreCalibrationPercent }
            rankingQualityPercent            = if ($null -eq $scorecard) { $null } else { $scorecard.rankingQualityPercent }
            finalistQualityPercent           = if ($null -eq $scorecard) { $null } else { $scorecard.finalistQualityPercent }
            failedChunkCount                 = if ($null -eq $scorecard) { $null } else { $scorecard.failedChunkCount }
            warningChunkCount                = if ($null -eq $scorecard) { $null } else { $scorecard.warningChunkCount }
            passedChunkCount                 = if ($null -eq $scorecard) { $null } else { $scorecard.passedChunkCount }
            negativeReturnTopPickCount       = if ($null -eq $scorecard) { $null } else { $scorecard.negativeReturnTopPickCount }
            weakTopPickCount                 = if ($null -eq $scorecard) { $null } else { $scorecard.weakTopPickCount }
            topImprovementActions            = if ($null -eq $scorecard) { @() } else { @($scorecard.topImprovementActions) }
        })

        $donePercent = [int][Math]::Floor((($index + 1) / [double]$SelectionModes.Count) * 100)
        Write-StepProgress $donePercent ("Completed scenario {0}/{1}: {2} => {3}" -f $scenarioNumber, $SelectionModes.Count, $mode, $scenarioStatus)
    }

    $completed = @($scenarioResults | Where-Object { $_.status -eq 'COMPLETED' })
    $failed = @($scenarioResults | Where-Object { $_.status -ne 'COMPLETED' })
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
    $aggregate = [pscustomobject][ordered]@{
        status                              = if ($failed.Count -gt 0) { 'REVIEW_WITH_FAILURES' } elseif (($overallScores | Where-Object { $_ -lt 85 }).Count -gt 0) { 'REVIEW_WITH_WARNINGS' } else { 'READY_FOR_NEXT_TRAINING_ITERATION' }
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
        scenarioResults                     = @($scenarioResults)
        recurringImprovementActions         = @($rankedActions)
        guardrails                          = @(
            'Review-only validation. No signal, paper fill, broker order, or live trading action is created.',
            'Scenario selection uses as-of features only; hidden future labels remain evaluator-only.',
            'Local Ollama/Granite model concurrency remains 1; scenarios are run sequentially.'
        )
    }

    $aggregate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8

    Write-Host ''
    Write-Host 'Step 87 scenario summary'
    $scenarioResults |
        Select-Object selectionMode, status, overallIntelligenceScorePercent, pendingImprovementPercent,
            pipelineReliabilityPercent, scoreCalibrationPercent, rankingQualityPercent,
            finalistQualityPercent, failedChunkCount, warningChunkCount, negativeReturnTopPickCount,
            weakTopPickCount |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Recurring improvement actions'
    $rankedActions | Format-Table -AutoSize

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
