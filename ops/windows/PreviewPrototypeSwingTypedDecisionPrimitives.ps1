[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [ValidateSet('FIXED_SYMBOL', 'RANDOM_VALIDATION', 'DIFFICULT_TRAPS', 'RECOVERY_OVEREXTENSION')]
    [string]$SelectionMode = 'FIXED_SYMBOL',

    [Parameter()]
    [ValidateRange(0, 500)]
    [int]$StartOffset = 0,

    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$CandidateLimit = 8,

    [Parameter()]
    [ValidateSet(5, 20, 60)]
    [int]$RankingHorizonSessions = 20,

    [Parameter()]
    [string]$ModelRef = 'Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M',

    [Parameter()]
    [string]$LlamaCliPath,

    [Parameter()]
    [ValidateRange(32, 512)]
    [int]$MaxTokens = 160,

    [Parameter()]
    [ValidateRange(10, 300)]
    [int]$TimeoutSeconds = 180,

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
    Write-Progress -Activity 'Step 89 llama.cpp typed decision primitive preview' -Status $Message -PercentComplete $Percent
    Write-Host ("[{0}%] {1}" -f $Percent, $Message)
}

function Resolve-LlamaCli {
    param([string]$RequestedPath)
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath)) {
            throw "LlamaCliPath does not exist: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    $command = Get-Command llama-cli -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $toolRoot = 'C:\MarketBrainTools\llama.cpp'
    if (Test-Path -LiteralPath $toolRoot) {
        $match = Get-ChildItem -Path $toolRoot -Filter 'llama-cli.exe' -Recurse |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not [string]::IsNullOrWhiteSpace($match)) {
            return $match
        }
    }
    throw 'llama-cli.exe was not found. Install llama.cpp under C:\MarketBrainTools\llama.cpp or pass -LlamaCliPath.'
}

function Get-FirstJsonObject {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $start = $Text.IndexOf('{')
    if ($start -lt 0) {
        return $null
    }
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = $start; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        if ($escaped) {
            $escaped = $false
            continue
        }
        if ($char -eq '\') {
            $escaped = $true
            continue
        }
        if ($char -eq '"') {
            $inString = -not $inString
            continue
        }
        if ($inString) {
            continue
        }
        if ($char -eq '{') {
            $depth++
        }
        elseif ($char -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return $null
}

function Test-InSet {
    param(
        [object]$Value,
        [object[]]$Allowed
    )
    return @($Allowed) -contains ([string]$Value)
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$safeModel = $ModelRef -replace '[^A-Za-z0-9._-]', '_'
$safeSelectionMode = $SelectionMode -replace '[^A-Za-z0-9._-]', '_'
$stem = "prototype-swing-typed-decision-primitives-$suffix-$safeModel-$safeSelectionMode-h$RankingHorizonSessions-offset$StartOffset-total$CandidateLimit"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$attemptPath = Join-Path $OutputDirectory "$stem-attempts.json"
$grammarPath = Join-Path $OutputDirectory "$stem.gbnf"
$logPath = Join-Path $OutputDirectory "$stem.log"

$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    Write-StepProgress 0 'Validating MarketBrain service health...'
    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-StepProgress 10 'Resolving llama-cli...'
    $llamaCli = Resolve-LlamaCli -RequestedPath $LlamaCliPath
    Write-Host "llama-cli: $llamaCli"

    Write-StepProgress 15 'Requesting Java-owned typed decision primitive candidates...'
    $body = [ordered]@{
        selectionMode          = $SelectionMode
        startOffset            = $StartOffset
        candidateLimit         = $CandidateLimit
        rankingHorizonSessions = $RankingHorizonSessions
    }
    if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
        $body['datasetRunId'] = $DatasetRunId
    }
    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-typed-decision-primitives" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec $TimeoutSeconds

    [string]$preview.grammar | Set-Content -LiteralPath $grammarPath -Encoding UTF8

    Write-Host 'Step 89: running local llama.cpp + GBNF typed decision primitive preview...'
    Write-Host "Selection mode: $SelectionMode; start offset: $StartOffset; candidates: $($preview.candidateCount)"
    Write-Host "Model ref: $ModelRef"
    Write-Host 'No database write, Ollama call, signal, paper fill, order, broker action, or live trading action will be created.'

    $attempts = @()
    $total = @($preview.candidates).Count
    for ($index = 0; $index -lt $total; $index++) {
        $candidate = @($preview.candidates)[$index]
        $candidateNumber = $index + 1
        $percent = [Math]::Min(95, [Math]::Floor(20 + (($candidateNumber - 1) * 70.0 / [Math]::Max(1, $total))))
        Write-StepProgress $percent ("Decisioning candidate {0}/{1}: {2}" -f $candidateNumber, $total, $candidate.symbol)

        $promptPath = Join-Path $OutputDirectory ("$stem-{0}-{1}-prompt.txt" -f $candidate.candidateId, $candidate.symbol)
        $rawPath = Join-Path $OutputDirectory ("$stem-{0}-{1}-llama-raw.txt" -f $candidate.candidateId, $candidate.symbol)
        $responsePath = Join-Path $OutputDirectory ("$stem-{0}-{1}-decision.json" -f $candidate.candidateId, $candidate.symbol)
        [string]$candidate.prompt | Set-Content -LiteralPath $promptPath -Encoding UTF8

        $stderrPath = Join-Path $OutputDirectory ("$stem-{0}-{1}-llama-stderr.txt" -f $candidate.candidateId, $candidate.symbol)
        $startedAt = Get-Date
        $llamaArguments = @(
            '-hf', $ModelRef,
            '--grammar-file', $grammarPath,
            '--no-conversation',
            '--no-display-prompt',
            '-f', $promptPath,
            '-n', ([string]$MaxTokens),
            '--temp', '0'
        )
        $process = Start-Process `
            -FilePath $llamaCli `
            -ArgumentList $llamaArguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $rawPath `
            -RedirectStandardError $stderrPath
        $elapsedMillis = [int](((Get-Date) - $startedAt).TotalMilliseconds)
        $stdoutText = if (Test-Path -LiteralPath $rawPath) { Get-Content -LiteralPath $rawPath -Raw } else { '' }
        $stderrText = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        $rawOutput = ($stdoutText + "`n" + $stderrText).Trim()
        $rawOutput | Set-Content -LiteralPath $rawPath -Encoding UTF8

        $jsonText = Get-FirstJsonObject -Text $rawOutput
        $parseable = $false
        $schemaValid = $false
        $businessValid = $false
        $decisionAligned = $false
        $warnings = @()
        $failures = @()
        $decision = $null
        if ($process.ExitCode -ne 0) {
            $failures += "LLAMA_EXIT_CODE_$($process.ExitCode)"
        }
        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            $failures += 'NO_JSON_OBJECT_FOUND'
        }
        else {
            $jsonText | Set-Content -LiteralPath $responsePath -Encoding UTF8
            try {
                $decision = $jsonText | ConvertFrom-Json
                $parseable = $true
            }
            catch {
                $failures += 'JSON_PARSE_FAILED'
            }
        }

        if ($parseable) {
            if ([string]$decision.candidateId -ne [string]$candidate.candidateId) {
                $failures += 'CANDIDATE_ID_MISMATCH'
            }
            if (-not (Test-InSet $decision.decision $preview.allowedDecisions)) {
                $failures += 'INVALID_DECISION_ENUM'
            }
            if (-not (Test-InSet $decision.riskBucket $preview.allowedRiskBuckets)) {
                $failures += 'INVALID_RISK_BUCKET_ENUM'
            }
            if (-not (Test-InSet $decision.trapDetected $preview.allowedTrapFlags)) {
                $failures += 'INVALID_TRAP_ENUM'
            }
            if (-not (Test-InSet $decision.scoreBand $preview.allowedScoreBands)) {
                $failures += 'INVALID_SCORE_BAND_ENUM'
            }
            if (-not (Test-InSet $decision.confidenceBand $preview.allowedConfidenceBands)) {
                $failures += 'INVALID_CONFIDENCE_BAND_ENUM'
            }
            if (-not (Test-InSet $decision.primaryReasonCode $preview.allowedReasonCodes)) {
                $failures += 'INVALID_REASON_CODE_ENUM'
            }
            $schemaValid = $failures.Count -eq 0
        }

        if ($schemaValid) {
            if ($decision.riskBucket -eq 'BLOCKED' -and $decision.decision -eq 'TOP_PICK') {
                $failures += 'BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK'
            }
            if ($candidate.javaTopPickEligibility -eq 'BLOCKED' -and $decision.decision -eq 'TOP_PICK') {
                $failures += 'JAVA_BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK'
            }
            if ($decision.decision -eq 'REJECT' -and @('HIGH', 'VERY_HIGH') -contains $decision.scoreBand) {
                $failures += 'REJECT_WITH_HIGH_SCORE_BAND'
            }
            if ($decision.riskBucket -eq 'BLOCKED' -and @('MEDIUM', 'HIGH', 'VERY_HIGH') -contains $decision.scoreBand) {
                $failures += 'BLOCKED_WITH_ELEVATED_SCORE_BAND'
            }
            if ($candidate.javaScoreCapHint -eq 'HARD_CAP_54' -and @('HIGH', 'VERY_HIGH') -contains $decision.scoreBand) {
                $failures += 'HARD_CAP_54_SCORE_BAND_VIOLATION'
            }
            if ($candidate.javaScoreCapHint -eq 'HARD_CAP_69' -and $decision.scoreBand -eq 'VERY_HIGH') {
                $failures += 'HARD_CAP_69_SCORE_BAND_VIOLATION'
            }
            if ([string]$decision.decision -ne [string]$candidate.javaDecision) {
                $warnings += 'DECISION_DIVERGED_FROM_JAVA_GUARDRAIL'
            }
            if ([string]$decision.riskBucket -ne [string]$candidate.javaRiskBucket) {
                $warnings += 'RISK_BUCKET_DIVERGED_FROM_JAVA_GUARDRAIL'
            }
            if ([string]$decision.scoreBand -ne [string]$candidate.javaScoreBand) {
                $warnings += 'SCORE_BAND_DIVERGED_FROM_JAVA_GUARDRAIL'
            }
            $businessValid = $failures.Count -eq 0
            $decisionAligned = ([string]$decision.decision -eq [string]$candidate.javaDecision) `
                -and ([string]$decision.riskBucket -eq [string]$candidate.javaRiskBucket) `
                -and ([string]$decision.scoreBand -eq [string]$candidate.javaScoreBand)
        }

        $warningArray = @($warnings | ForEach-Object { [string]$_ })
        $failureArray = @($failures | ForEach-Object { [string]$_ })
        $attemptRecord = [pscustomobject][ordered]@{
            candidateId                            = $candidate.candidateId
            symbol                                 = $candidate.symbol
            promptPath                             = $promptPath
            rawOutputPath                          = $rawPath
            stderrPath                             = $stderrPath
            llamaExitCode                          = $process.ExitCode
            responsePath                           = if (Test-Path -LiteralPath $responsePath) { $responsePath } else { $null }
            elapsedMillis                          = $elapsedMillis
            parseableJson                          = $parseable
            schemaValid                            = $schemaValid
            businessValid                          = $businessValid
            decisionAlignedWithJavaGuardrail        = $decisionAligned
            modelDecision                          = if ($null -eq $decision) { $null } else { $decision.decision }
            modelRiskBucket                        = if ($null -eq $decision) { $null } else { $decision.riskBucket }
            modelTrapDetected                      = if ($null -eq $decision) { $null } else { $decision.trapDetected }
            modelScoreBand                         = if ($null -eq $decision) { $null } else { $decision.scoreBand }
            modelConfidenceBand                    = if ($null -eq $decision) { $null } else { $decision.confidenceBand }
            modelPrimaryReasonCode                 = if ($null -eq $decision) { $null } else { $decision.primaryReasonCode }
            javaDecision                           = $candidate.javaDecision
            javaRiskBucket                         = $candidate.javaRiskBucket
            javaTrapDetected                       = $candidate.javaTrapDetected
            javaScoreBand                          = $candidate.javaScoreBand
            javaConfidenceBand                     = $candidate.javaConfidenceBand
            javaPrimaryReasonCode                  = $candidate.javaPrimaryReasonCode
            javaFeaturePriorScore                  = $candidate.javaFeaturePriorScore
            javaQualityAnchorScore                 = $candidate.javaQualityAnchorScore
            javaQualityAnchorRank                  = $candidate.javaQualityAnchorRank
            javaScoreCapHint                       = $candidate.javaScoreCapHint
            javaTopPickEligibility                 = $candidate.javaTopPickEligibility
            actualRank                             = $candidate.actualRank
            targetNetReturnPercent                 = $candidate.targetNetReturnPercent
            targetMaximumDrawdownPercent           = $candidate.targetMaximumDrawdownPercent
            warnings                               = $warningArray
            failures                               = $failureArray
        }
        $attempts += $attemptRecord
        @($attempts) |
            ConvertTo-Json -Depth 80 |
            Set-Content -LiteralPath $attemptPath -Encoding UTF8
    }

    Write-StepProgress 92 'Summarizing typed decision primitive results...'
    $attemptArray = @($attempts | ForEach-Object { $_ })
    $schemaValidCount = @($attemptArray | Where-Object { $_.schemaValid }).Count
    $businessValidCount = @($attemptArray | Where-Object { $_.businessValid }).Count
    $alignedCount = @($attemptArray | Where-Object { $_.decisionAlignedWithJavaGuardrail }).Count
    $topPickCount = @($attemptArray | Where-Object { $_.modelDecision -eq 'TOP_PICK' }).Count
    $blockedViolationCount = @($attemptArray | Where-Object { @($_.failures) -contains 'BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK' -or @($_.failures) -contains 'JAVA_BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK' }).Count

    $summary = [pscustomobject][ordered]@{
        status                         = if ($businessValidCount -eq $total) { 'REVIEW_REQUIRED' } else { 'REVIEW_WITH_WARNINGS' }
        datasetRunId                   = $preview.datasetRunId
        selectionMode                  = $SelectionMode
        modelRef                       = $ModelRef
        startOffset                    = $StartOffset
        candidateLimit                 = $CandidateLimit
        candidateCount                 = $total
        rankingHorizonSessions         = $RankingHorizonSessions
        decisionContractVersion        = $preview.decisionContractVersion
        grammarVersion                 = $preview.grammarVersion
        schemaValidCount               = $schemaValidCount
        businessValidCount             = $businessValidCount
        decisionAlignedWithJavaCount   = $alignedCount
        topPickCount                   = $topPickCount
        blockedPromotionViolationCount = $blockedViolationCount
        schemaValidPercent             = if ($total -eq 0) { 0 } else { [math]::Round($schemaValidCount * 100.0 / $total, 2) }
        businessValidPercent           = if ($total -eq 0) { 0 } else { [math]::Round($businessValidCount * 100.0 / $total, 2) }
        javaAlignmentPercent           = if ($total -eq 0) { 0 } else { [math]::Round($alignedCount * 100.0 / $total, 2) }
        grammarPath                    = $grammarPath
        attemptPath                    = $attemptPath
        databaseWritesPerformed        = $false
        ollamaCallCount                = 0
        llamaCppCallCount              = $total
        signalsCreated                 = 0
        ordersCreated                  = 0
        actionExecutionEnabled         = $false
        attempts                       = @($attemptArray)
        detail                         = 'Step 89 used local llama.cpp with GBNF to produce enum/band typed decision primitives. Java guardrails remained authoritative. No trading action was created.'
    }

    $attemptArray | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $attemptPath -Encoding UTF8
    $summary | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-StepProgress 100 'Typed decision primitive preview complete.'
    $summary |
        Select-Object status, selectionMode, modelRef, candidateCount, schemaValidCount, businessValidCount, `
            decisionAlignedWithJavaCount, schemaValidPercent, businessValidPercent, javaAlignmentPercent, `
            topPickCount, blockedPromotionViolationCount, llamaCppCallCount, databaseWritesPerformed, `
            ollamaCallCount, signalsCreated, ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Candidate decision summary'
    $attemptArray |
        Select-Object candidateId, symbol, modelDecision, modelRiskBucket, modelScoreBand, javaDecision, `
            javaRiskBucket, javaScoreBand, businessValid, actualRank, targetNetReturnPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'STEP 89 COMPLETE: local typed decision primitive preview finished.'
    Write-Host 'This is not a trading signal and did not create any order, paper fill, broker action, or live trading action.'
    Write-Host "Result: $resultPath"
    Write-Host "Attempts: $attemptPath"
    Write-Host "Grammar: $grammarPath"
    Write-Host "Log: $logPath"
}
finally {
    Write-Progress -Activity 'Step 89 llama.cpp typed decision primitive preview' -Completed
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
