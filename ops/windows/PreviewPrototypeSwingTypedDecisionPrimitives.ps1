#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [ValidateSet('FIXED_SYMBOL', 'RANDOM_VALIDATION', 'DIFFICULT_TRAPS', 'RECOVERY_OVEREXTENSION', 'BALANCED_VALIDATION', 'CONTRAST_VALIDATION')]
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
    [ValidateSet('INDEPENDENT', 'BASELINE_CONSTRAINED')]
    [string]$EvaluationMode = 'INDEPENDENT',

    [Parameter()]
    [string]$LlamaCliPath,

    [string]$ModelPath,
    [string]$SnapshotPath,
    [ValidateRange(0, 1)][double]$Temperature = 0,
    [ValidateRange(-1, 2147483646)][int]$Seed = -1,
    [scriptblock]$Heartbeat,

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
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')

function Write-StepProgress {
    param(
        [int]$Percent,
        [string]$Message
    )
    Write-Progress -Activity 'Step 89 llama.cpp typed decision primitive preview' -Status $Message -PercentComplete $Percent
    Write-Host ("[{0}%] {1}" -f $Percent, $Message)
}

function Wait-MarketBrainHealth {
    param(
        [string]$ServiceBaseUrl,
        [int]$Attempts = 18,
        [int]$DelaySeconds = 5
    )
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $health = Invoke-RestMethod "$ServiceBaseUrl/actuator/health" -TimeoutSec 30
            if ($health.status -eq 'UP') {
                Write-Host "MarketBrain health is UP on attempt $attempt/$Attempts." -ForegroundColor Green
                return
            }
            Write-Host "MarketBrain health attempt $attempt/$Attempts returned status: $($health.status)" -ForegroundColor Yellow
        }
        catch {
            Write-Host "MarketBrain health attempt $attempt/$Attempts failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    throw "MarketBrain service did not become healthy after $Attempts attempts."
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


function Test-InSet {
    param(
        [object]$Value,
        [object[]]$Allowed
    )
    return $Value -is [string] -and @($Allowed) -ccontains $Value
}

function Invoke-LlamaCliProcess {
    param(
        [string]$ExecutablePath,
        [string[]]$Arguments,
        [string]$StandardOutputPath,
        [string]$StandardErrorPath,
        [int]$ProcessTimeoutSeconds,
        [string]$StandardInputText
    )
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $ExecutablePath
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardInput = -not [string]::IsNullOrEmpty($StandardInputText)
    $processInfo.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        [void]$processInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    try {
    $started = $process.Start()
    if (-not $started) {
        throw "Failed to start llama-cli process: $ExecutablePath"
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not [string]::IsNullOrEmpty($StandardInputText)) {
        $process.StandardInput.Write($StandardInputText)
        $process.StandardInput.Close()
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $completed = $false
    while ($clock.Elapsed.TotalSeconds -lt $ProcessTimeoutSeconds) {
        if ($process.WaitForExit(1000)) { $completed = $true; break }
        if ([int]$clock.Elapsed.TotalSeconds % 15 -eq 0) {
            Write-Host ('Model process active: elapsed={0:N0}s; timeout={1}s' -f $clock.Elapsed.TotalSeconds, $ProcessTimeoutSeconds)
            if ($Heartbeat) { & $Heartbeat }
        }
    }
    $timedOut = -not $completed
    if ($timedOut) {
        try {
            $process.Kill($true)
        }
        catch {
            Write-Warning "Failed to kill timed-out llama-cli process: $($_.Exception.Message)"
        }
    }
    else {
        $process.WaitForExit()
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $stdout | Set-Content -LiteralPath $StandardOutputPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $StandardErrorPath -Encoding UTF8

    [pscustomobject][ordered]@{
        exitCode = if ($timedOut) { -999 } else { $process.ExitCode }
        timedOut = $timedOut
        stdout = $stdout
        stderr = $stderr
    }
    }
    finally {
        # Also release the child on Ctrl+C or checkpoint errors; never leave an orphan inference.
        try { if (-not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(5000) } } catch { }
        $process.Dispose()
    }
}

function Get-LlamaCliCapabilities {
    param(
        [string]$ExecutablePath,
        [int]$ProcessTimeoutSeconds,
        [string]$OutputDirectory,
        [string]$Stem
    )

    $helpOutPath = Join-Path $OutputDirectory "$Stem-llama-help.txt"
    $helpErrPath = Join-Path $OutputDirectory "$Stem-llama-help-stderr.txt"
    $helpProcess = Invoke-LlamaCliProcess `
        -ExecutablePath $ExecutablePath `
        -Arguments @('--help') `
        -StandardOutputPath $helpOutPath `
        -StandardErrorPath $helpErrPath `
        -ProcessTimeoutSeconds $ProcessTimeoutSeconds `
        -StandardInputText ''
    $helpText = (($helpProcess.stdout + "`n" + $helpProcess.stderr) -join '').Trim()
    [pscustomobject][ordered]@{
        helpText          = $helpText
        helpStderr        = $helpProcess.stderr
        helpExitCode      = $helpProcess.exitCode
        helpTimedOut      = $helpProcess.timedOut
        supportsSingleTurn = ($helpText -match '(^|\s)(-st|--single-turn)(\s|,|$)')
        supportsNoDisplayPrompt = ($helpText -match '--no-display-prompt')
        supportsGrammarFile = ($helpText -match '--grammar-file')
    }
}

function ConvertTo-GbnfQuotedJsonString {
    param([string]$Value)
    return '"\"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '\""'
}

function Get-SafeRejectScoreBand {
    param([object]$Candidate)
    $scoreBand = [string]$Candidate.javaScoreBand
    if (@('VERY_LOW', 'LOW', 'MEDIUM') -contains $scoreBand) {
        return $scoreBand
    }
    if ([string]$Candidate.javaRiskBucket -eq 'BLOCKED') {
        return 'LOW'
    }
    return 'MEDIUM'
}

function New-TypedDecisionCandidateGrammar {
    param([object]$Candidate)

    $rows = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    function Add-TypedDecisionRow {
        param(
            [System.Collections.Generic.List[string]]$Rows,
            [hashtable]$Seen,
            [string]$CandidateId,
            [string]$Decision,
            [string]$RiskBucket,
            [string]$TrapDetected,
            [string]$ScoreBand,
            [string]$ConfidenceBand,
            [string]$PrimaryReasonCode
        )

        if ($Decision -eq 'REJECT' -and @('HIGH', 'VERY_HIGH') -contains $ScoreBand) {
            return
        }
        if ($RiskBucket -eq 'BLOCKED' -and @('MEDIUM', 'HIGH', 'VERY_HIGH') -contains $ScoreBand) {
            return
        }
        if ($RiskBucket -eq 'BLOCKED' -and $Decision -ne 'REJECT') {
            return
        }
        $key = @($Decision, $RiskBucket, $TrapDetected, $ScoreBand, $ConfidenceBand, $PrimaryReasonCode) -join '|'
        if ($Seen.ContainsKey($key)) {
            return
        }
        $Seen[$key] = $true

        $row = @(
            '"{" ws',
            (ConvertTo-GbnfQuotedJsonString 'candidateId'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $CandidateId), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'decision'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $Decision), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'riskBucket'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $RiskBucket), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'trapDetected'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $TrapDetected), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'scoreBand'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $ScoreBand), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'confidenceBand'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $ConfidenceBand), 'ws "," ws',
            (ConvertTo-GbnfQuotedJsonString 'primaryReasonCode'), 'ws ":" ws', (ConvertTo-GbnfQuotedJsonString $PrimaryReasonCode), 'ws',
            '"}"'
        ) -join ' '
        $Rows.Add($row)
    }

    Add-TypedDecisionRow `
        -Rows $rows `
        -Seen $seen `
        -CandidateId ([string]$Candidate.candidateId) `
        -Decision ([string]$Candidate.javaDecision) `
        -RiskBucket ([string]$Candidate.javaRiskBucket) `
        -TrapDetected ([string]$Candidate.javaTrapDetected) `
        -ScoreBand ([string]$Candidate.javaScoreBand) `
        -ConfidenceBand ([string]$Candidate.javaConfidenceBand) `
        -PrimaryReasonCode ([string]$Candidate.javaPrimaryReasonCode)

    if ([string]$Candidate.javaDecision -ne 'REJECT') {
        $rejectReason = if ([string]$Candidate.javaPrimaryReasonCode -in @('TRAP_RISK', 'OVEREXTENSION_RISK', 'BLOCKED_BY_RISK')) {
            [string]$Candidate.javaPrimaryReasonCode
        }
        else {
            'MIXED_EVIDENCE'
        }
        Add-TypedDecisionRow `
            -Rows $rows `
            -Seen $seen `
            -CandidateId ([string]$Candidate.candidateId) `
            -Decision 'REJECT' `
            -RiskBucket ([string]$Candidate.javaRiskBucket) `
            -TrapDetected 'YES' `
            -ScoreBand (Get-SafeRejectScoreBand -Candidate $Candidate) `
            -ConfidenceBand ([string]$Candidate.javaConfidenceBand) `
            -PrimaryReasonCode $rejectReason
    }

    if ($rows.Count -eq 0) {
        Add-TypedDecisionRow `
            -Rows $rows `
            -Seen $seen `
            -CandidateId ([string]$Candidate.candidateId) `
            -Decision 'REJECT' `
            -RiskBucket 'HIGH' `
            -TrapDetected 'YES' `
            -ScoreBand 'LOW' `
            -ConfidenceBand 'MEDIUM' `
            -PrimaryReasonCode 'MIXED_EVIDENCE'
    }

    $grammarLines = [System.Collections.Generic.List[string]]::new()
    $rowNames = [System.Collections.Generic.List[string]]::new()
    for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
        $rowName = 'row' + ($rowIndex + 1)
        $rowNames.Add($rowName)
        $grammarLines.Add($rowName + ' ::= ' + $rows[$rowIndex])
    }
    $grammarLines.Insert(0, 'root ::= ' + ($rowNames -join ' | '))
    $grammarLines.Add('ws ::= [ \t\n]*')
    return ($grammarLines -join "`n")
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$safeModel = $ModelRef -replace '[^A-Za-z0-9._-]', '_'
$safeSelectionMode = $SelectionMode -replace '[^A-Za-z0-9._-]', '_'
$runStamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$stem = "typed-decision-$runStamp"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$scratchDirectory = Join-Path $OutputDirectory ("_step89_tmp_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$grammarPath = Join-Path $scratchDirectory "grammar.gbnf"

$transcriptStarted = $false
$attempts = @()
$modelInvocationCount = 0
$runClock = [System.Diagnostics.Stopwatch]::StartNew()
$evidence = $null
$grammarMode = if ($EvaluationMode -eq 'INDEPENDENT') { 'INDEPENDENT_SCHEMA_GBNF_V1' } else { 'CANDIDATE_SPECIFIC_SEMANTIC_GBNF' }
$runnerIdentity = [pscustomobject]@{
    version = 'TYPED_DECISION_RUNNER_V3'
    scriptSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    evaluationHelperSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1') -Algorithm SHA256).Hash
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
}
try {
    New-Item -ItemType Directory -Path $scratchDirectory -Force | Out-Null
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    Write-StepProgress 0 'Validating MarketBrain service health...'
    if (-not $SnapshotPath) { Wait-MarketBrainHealth -ServiceBaseUrl $BaseUrl }

    Write-StepProgress 10 'Resolving llama-cli...'
    $llamaCli = Resolve-LlamaCli -RequestedPath $LlamaCliPath
    Write-Host "llama-cli: $llamaCli"
    $llamaCapabilities = Get-LlamaCliCapabilities `
        -ExecutablePath $llamaCli `
        -ProcessTimeoutSeconds 30 `
        -OutputDirectory $scratchDirectory `
        -Stem 'capabilities'
    Write-Host ("llama-cli capabilities: singleTurn={0}; grammarFile={1}; noDisplayPrompt={2}; helpExitCode={3}" -f `
            $llamaCapabilities.supportsSingleTurn, `
            $llamaCapabilities.supportsGrammarFile, `
            $llamaCapabilities.supportsNoDisplayPrompt, `
            $llamaCapabilities.helpExitCode)
    if (-not $llamaCapabilities.supportsGrammarFile -or -not $llamaCapabilities.supportsSingleTurn -or $llamaCapabilities.helpExitCode -ne 0) {
        throw 'This evaluation requires working --grammar-file and --single-turn support. See embedded help evidence.'
    }
    if ($Seed -ge 0 -and $llamaCapabilities.helpText -notmatch '--seed') { throw 'This evaluation requires --seed support.' }
    if ($ModelPath -and -not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) { throw 'Local model file not found.' }

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
    if ($SnapshotPath) {
        if ($EvaluationMode -ne 'INDEPENDENT') { throw 'Snapshot evaluation must remain independent.' }
        $preview = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
        if ($preview.datasetRunId -ne $DatasetRunId -or $preview.selectionMode -ne $SelectionMode -or
            $preview.rankingHorizonSessions -ne $RankingHorizonSessions -or $preview.candidates.Count -ne $CandidateLimit) {
            throw 'Snapshot identity does not match requested evaluation.'
        }
    } else {
    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-typed-decision-primitives" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec $TimeoutSeconds
    }
    if ($EvaluationMode -eq 'INDEPENDENT' -and $preview.decisionContractVersion -ne 'MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5') {
        throw 'Independent evaluation requires the V5 Java service. Rebuild/redeploy marketbrain-service first.'
    }
    Write-Host 'Step 89: running local llama.cpp + GBNF typed decision primitive preview...'
    Write-Host "Selection mode: $SelectionMode; start offset: $StartOffset; candidates: $($preview.candidateCount)"
    Write-Host "Model ref: $ModelRef"
    Write-Host "Evaluation mode: $EvaluationMode; grammar: $grammarMode"
    Write-Host 'No database write, Ollama call, signal, paper fill, order, broker action, or live trading action will be created.'

    $attempts = @()
    $total = @($preview.candidates).Count
    if ($total -eq 0) { throw 'No eligible candidates returned; an empty run cannot pass.' }
    if ($EvaluationMode -eq 'INDEPENDENT') {
        foreach ($item in $preview.candidates) {
            if ([string]::IsNullOrWhiteSpace($item.independentPrompt)) { throw 'Java returned a missing independent prompt.' }
        }
    }
    for ($index = 0; $index -lt $total; $index++) {
        $candidate = @($preview.candidates)[$index]
        $candidateNumber = $index + 1
        $percent = [Math]::Min(95, [Math]::Floor(20 + (($candidateNumber - 1) * 70.0 / [Math]::Max(1, $total))))
        Write-StepProgress $percent ("Decisioning candidate {0}/{1}: {2}" -f $candidateNumber, $total, $candidate.symbol)

        $shortCandidateStem = "{0}-{1}" -f $candidate.candidateId, $candidate.symbol
        $grammarPath = Join-Path $scratchDirectory "$shortCandidateStem.gbnf"
        $promptPath = Join-Path $scratchDirectory "$shortCandidateStem-prompt.txt"
        $rawPath = Join-Path $scratchDirectory "$shortCandidateStem-raw.txt"
        $responsePath = Join-Path $scratchDirectory "$shortCandidateStem-decision.json"
        $candidatePrompt = if ($EvaluationMode -eq 'INDEPENDENT') { [string]$candidate.independentPrompt } else { [string]$candidate.prompt }
        $candidatePrompt | Set-Content -LiteralPath $promptPath -Encoding UTF8
        $candidateGrammar = if ($EvaluationMode -eq 'INDEPENDENT') {
            New-IndependentDecisionGrammar -Candidate $candidate -Grammar $preview.grammar
        } else { New-TypedDecisionCandidateGrammar -Candidate $candidate }
        $candidateGrammar | Set-Content -LiteralPath $grammarPath -Encoding UTF8

        $stderrPath = Join-Path $scratchDirectory "$shortCandidateStem-stderr.txt"
        $fallbackRawPath = Join-Path $scratchDirectory "$shortCandidateStem-fallback-raw.txt"
        $fallbackStderrPath = Join-Path $scratchDirectory "$shortCandidateStem-fallback-stderr.txt"
        $startedAt = Get-Date
        $llamaExitCommand = if ($llamaCapabilities.supportsSingleTurn) { '' } else { "/exit`n" }
        $modelArguments = if ($ModelPath) { @('-m', $ModelPath) } else { @('-hf', $ModelRef) }
        $llamaArguments = $modelArguments + @(
            '--grammar-file', $grammarPath,
            '-f', $promptPath,
            '-n', ([string]$MaxTokens),
            '--temp', $Temperature.ToString([Globalization.CultureInfo]::InvariantCulture)
        )
        if ($Seed -ge 0) { $llamaArguments += @('--seed', [string]$Seed) }
        if ($llamaCapabilities.supportsSingleTurn) {
            $llamaArguments += '-st'
        }
        if ($llamaCapabilities.supportsNoDisplayPrompt) {
            $llamaArguments += '--no-display-prompt'
        }
        $modelInvocationCount++
        $process = Invoke-LlamaCliProcess `
            -ExecutablePath $llamaCli `
            -Arguments $llamaArguments `
            -StandardOutputPath $rawPath `
            -StandardErrorPath $stderrPath `
            -ProcessTimeoutSeconds $TimeoutSeconds `
            -StandardInputText $llamaExitCommand
        $usedFallbackInvocation = $false
        $primaryProcess = $process
        if ($process.exitCode -ne 0 -and $EvaluationMode -eq 'BASELINE_CONSTRAINED') {
            Write-Host ("llama-cli primary invocation failed for {0} with exit code {1}; retrying with minimal stdin-exit arguments." -f $candidate.symbol, $process.exitCode) -ForegroundColor Yellow
            $fallbackArguments = $modelArguments + @(
                '--grammar-file', $grammarPath,
                '-f', $promptPath,
                '-n', ([string]$MaxTokens),
                '--temp', $Temperature.ToString([Globalization.CultureInfo]::InvariantCulture)
            )
            if ($Seed -ge 0) { $fallbackArguments += @('--seed', [string]$Seed) }
            if ($llamaCapabilities.supportsSingleTurn) {
                $fallbackArguments += '-st'
            }
            $modelInvocationCount++
            $process = Invoke-LlamaCliProcess `
                -ExecutablePath $llamaCli `
                -Arguments $fallbackArguments `
                -StandardOutputPath $fallbackRawPath `
                -StandardErrorPath $fallbackStderrPath `
                -ProcessTimeoutSeconds $TimeoutSeconds `
                -StandardInputText $llamaExitCommand
            $usedFallbackInvocation = $true
        }
        $elapsedMillis = [int](((Get-Date) - $startedAt).TotalMilliseconds)
        $effectiveRawPath = if ($usedFallbackInvocation) { $fallbackRawPath } else { $rawPath }
        $effectiveStderrPath = if ($usedFallbackInvocation) { $fallbackStderrPath } else { $stderrPath }
        $stdoutText = if (Test-Path -LiteralPath $effectiveRawPath) { [System.IO.File]::ReadAllText($effectiveRawPath) } else { '' }
        $stderrText = if (Test-Path -LiteralPath $effectiveStderrPath) { [System.IO.File]::ReadAllText($effectiveStderrPath) } else { '' }
        $rawOutput = $stdoutText.Trim()

        $assessment = Test-TypedDecisionResponse -Text $rawOutput -Prompt $candidatePrompt -Candidate $candidate -ExitCode $process.exitCode -TimedOut $process.timedOut -EvaluationMode $EvaluationMode
        $decision = $assessment.decision
        $parseable = $assessment.parseableJson
        $schemaValid = $assessment.schemaValid
        $businessValid = $assessment.businessValid
        $decisionAligned = $assessment.aligned
        $warnings = @($assessment.warnings)
        $failures = @($assessment.failures)
        $reasonWarnings = @($assessment.reasonEvidenceWarnings)
        $expectedDecisions = @($assessment.diagnosticExpectedDecisions)
        $diagnosticFailures = @($assessment.diagnosticFailures)
        $diagnosticPassed = $assessment.diagnosticPassed
        if ($assessment.extraction.json) {
            $assessment.extraction.json | Set-Content -LiteralPath $responsePath -Encoding UTF8
        }
        $warningArray = @($warnings | ForEach-Object { [string]$_ })
        $failureArray = @($failures | ForEach-Object { [string]$_ })
        $responseText = if (Test-Path -LiteralPath $responsePath) { [System.IO.File]::ReadAllText($responsePath) } else { $null }
        $attemptRecord = [pscustomobject][ordered]@{
            candidateId                            = $candidate.candidateId
            symbol                                 = $candidate.symbol
            evaluationMode                         = $EvaluationMode
            evidenceCategory                       = if ($candidate.PSObject.Properties['evidenceCategory']) { $candidate.evidenceCategory } else { 'UNAVAILABLE' }
            hardExclusionReason                    = if ($candidate.PSObject.Properties['hardExclusionReason']) { $candidate.hardExclusionReason } else { 'UNAVAILABLE' }
            grammar                                = $candidateGrammar
            prompt                                 = $candidatePrompt
            promptCharacterCount                   = $candidatePrompt.Length
            promptFileSha256                       = (Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash
            grammarFileSha256                      = (Get-FileHash -LiteralPath $grammarPath -Algorithm SHA256).Hash
            offlineCandidateEvidence               = $candidate
            diagnosticExpectedDecisions            = $expectedDecisions
            diagnosticPassed                       = $diagnosticPassed
            diagnosticFailures                     = $diagnosticFailures
            reasonEvidenceWarnings                 = $reasonWarnings
            rawOutput                              = $rawOutput
            extraction                             = $assessment.extraction
            failureStage                           = $assessment.failureStage
            stdout                                 = $stdoutText
            stderr                                 = $stderrText
            primaryExitCode                        = $primaryProcess.exitCode
            primaryStderr                          = $primaryProcess.stderr
            primaryStdout                          = $primaryProcess.stdout
            invocationArguments                    = $llamaArguments
            temperature                            = $Temperature
            seed                                   = $Seed
            modelPath                              = $ModelPath
            maxTokens                              = $MaxTokens
            invocationTimeoutSeconds               = $TimeoutSeconds
            responseJson                           = $responseText
            llamaSupportsSingleTurn                = $llamaCapabilities.supportsSingleTurn
            llamaSupportsGrammarFile               = $llamaCapabilities.supportsGrammarFile
            llamaSupportsNoDisplayPrompt           = $llamaCapabilities.supportsNoDisplayPrompt
            usedFallbackInvocation                 = $usedFallbackInvocation
            llamaExitCode                          = $process.exitCode
            llamaTimedOut                          = $process.timedOut
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
            targetBenchmarkExcessReturnPercent      = $candidate.targetBenchmarkExcessReturnPercent
            targetMaximumDrawdownPercent           = $candidate.targetMaximumDrawdownPercent
            warnings                               = $warningArray
            failures                               = $failureArray
        }
        $attempts += $attemptRecord
        $evidence = [pscustomobject][ordered]@{
            status                       = 'RUNNING'
            datasetRunId                 = $preview.datasetRunId
            selectionMode                = $SelectionMode
            modelRef                     = $ModelRef
            evaluationMode               = $EvaluationMode
            runnerIdentity               = $runnerIdentity
            asOf                         = $preview.asOf
            labelThrough                 = $preview.labelThrough
            startOffset                  = $StartOffset
            candidateLimit               = $CandidateLimit
            completedCandidateCount      = @($attempts).Count
            candidateCount               = $total
            rankingHorizonSessions       = $RankingHorizonSessions
            decisionContractVersion      = $preview.decisionContractVersion
            grammarVersion               = $preview.grammarVersion
            evidenceMode                 = 'COMPACT_EMBEDDED'
            grammarMode                  = $grammarMode
            generatedFileCount           = 2
            generatedFiles               = @($resultPath, $logPath)
            grammar                      = 'Exact inference grammar is embedded in attempts[].grammar; offline evidence is never appended to the prompt.'
            llamaHelp                    = $llamaCapabilities.helpText
            llamaHelpStderr              = $llamaCapabilities.helpStderr
            llamaHelpExitCode            = $llamaCapabilities.helpExitCode
            llamaHelpTimedOut            = $llamaCapabilities.helpTimedOut
            llamaSupportsSingleTurn      = $llamaCapabilities.supportsSingleTurn
            llamaSupportsGrammarFile     = $llamaCapabilities.supportsGrammarFile
            llamaSupportsNoDisplayPrompt = $llamaCapabilities.supportsNoDisplayPrompt
            databaseWritesPerformed      = $false
            ollamaCallCount              = 0
            llamaCppCallCount            = $modelInvocationCount
            signalsCreated               = 0
            ordersCreated                = 0
            actionExecutionEnabled       = $false
            attempts                     = @($attempts)
            detail                       = 'Partial Step 89 compact evidence checkpoint. The run is still in progress or was interrupted before final summary.'
        }
        Save-TypedDecisionEvidence -Evidence $evidence -Path $resultPath
        Write-Host ("Candidate {0}/{1} complete: schema={2}; policy={3}; decision={4}; elapsed={5:N1}s; failures={6}" -f `
            $candidateNumber, $total, $schemaValid, $businessValid, $attemptRecord.modelDecision, ($elapsedMillis / 1000.0), ($failureArray -join ','))
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
        evaluationMode                 = $EvaluationMode
        runnerIdentity                 = $runnerIdentity
        asOf                           = $preview.asOf
        labelThrough                   = $preview.labelThrough
        elapsedSeconds                 = [math]::Round($runClock.Elapsed.TotalSeconds, 2)
        evaluation                     = Get-TypedDecisionEvaluation -Attempts $attemptArray
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
        evidenceMode                   = 'COMPACT_EMBEDDED'
        grammarMode                    = $grammarMode
        generatedFileCount             = 2
        generatedFiles                 = @($resultPath, $logPath)
        grammar                        = 'Exact inference grammar is embedded in attempts[].grammar; offline candidate evidence is not sent to the model.'
        llamaHelp                      = $llamaCapabilities.helpText
        llamaHelpStderr                = $llamaCapabilities.helpStderr
        llamaHelpExitCode              = $llamaCapabilities.helpExitCode
        llamaHelpTimedOut              = $llamaCapabilities.helpTimedOut
        llamaSupportsSingleTurn        = $llamaCapabilities.supportsSingleTurn
        llamaSupportsGrammarFile       = $llamaCapabilities.supportsGrammarFile
        llamaSupportsNoDisplayPrompt   = $llamaCapabilities.supportsNoDisplayPrompt
        databaseWritesPerformed        = $false
        ollamaCallCount                = 0
        llamaCppCallCount              = $modelInvocationCount
        signalsCreated                 = 0
        ordersCreated                  = 0
        actionExecutionEnabled         = $false
        attempts                       = @($attemptArray)
        detail                         = 'Step 89 used local llama.cpp with GBNF to produce enum/band typed decision primitives. Java guardrails remained authoritative. No trading action was created.'
    }

    if (@($summary.evaluation.warnings).Count -gt 0) { $summary.status = 'REVIEW_WITH_WARNINGS' }
    Save-TypedDecisionEvidence -Evidence $summary -Path $resultPath

    Write-StepProgress 100 'Typed decision primitive preview complete.'
    $summary |
        Select-Object status, selectionMode, evaluationMode, modelRef, elapsedSeconds, candidateCount, schemaValidCount, businessValidCount, `
            decisionAlignedWithJavaCount, schemaValidPercent, businessValidPercent, javaAlignmentPercent, `
            topPickCount, blockedPromotionViolationCount, llamaCppCallCount, databaseWritesPerformed, `
            ollamaCallCount, signalsCreated, ordersCreated, actionExecutionEnabled |
        Format-List
    Write-Host 'Independent evaluation diagnostics (Java agreement is not investment accuracy):'
    $summary.evaluation | Format-List

    Write-Host ''
    Write-Host 'Candidate decision summary'
    $attemptArray |
        Select-Object candidateId, symbol, modelDecision, modelRiskBucket, modelScoreBand, javaDecision, `
            javaRiskBucket, javaScoreBand, businessValid, actualRank, targetNetReturnPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'STEP 89 COMPLETE: local typed decision primitive preview finished.'
    Write-Host 'This is not a trading signal and did not create any order, paper fill, broker action, or live trading action.'
    Write-Host 'Compact evidence mode: result JSON embeds attempts, prompts, grammar, llama help, raw output, stderr, and parsed responses.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
catch {
    $failureEvidence = [pscustomobject][ordered]@{
        status = 'FAILED'
        datasetRunId = $DatasetRunId
        modelRef = $ModelRef
        evaluationMode = $EvaluationMode
        runnerIdentity = $runnerIdentity
        selectionMode = $SelectionMode
        elapsedSeconds = $runClock.Elapsed.TotalSeconds
        errorMessage = $_.Exception.Message
        exceptionType = $_.Exception.GetType().FullName
        scriptStackTrace = $_.ScriptStackTrace
        llamaCppCallCount = $modelInvocationCount
        completedCandidateCount = $attempts.Count
        attempts = $attempts
        previousCheckpoint = $evidence
        actionExecutionEnabled = $false
        databaseWritesPerformed = $false
        ollamaCallCount = 0
        signalsCreated = 0
        ordersCreated = 0
    }
    Save-TypedDecisionEvidence -Evidence $failureEvidence -Path $resultPath
    throw
}
finally {
    Write-Progress -Activity 'Step 89 llama.cpp typed decision primitive preview' -Completed
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
    if (Test-Path -LiteralPath $scratchDirectory) {
        $resolvedScratch = [System.IO.Path]::GetFullPath($scratchDirectory)
        $resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($resolvedScratch.StartsWith($resolvedOutput, [System.StringComparison]::OrdinalIgnoreCase) -and
            [System.IO.Path]::GetFileName($resolvedScratch).StartsWith('_step89_tmp_')) {
            Remove-Item -LiteralPath $resolvedScratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
