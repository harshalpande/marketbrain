# Mocked end-to-end runner test: never starts llama.cpp or contacts HTTP/database services.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$priorCalls = $env:MARKETBRAIN_OFFLINE_TEST_CALLS
$priorOldServer = $env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER
$priorContrastPass = $env:MARKETBRAIN_OFFLINE_CONTRAST_PASS
$env:MARKETBRAIN_OFFLINE_CONTRAST_PASS = '0'
$env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER = '0'
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('marketbrain-runner-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$sourcePath = Join-Path $PSScriptRoot 'PreviewPrototypeSwingTypedDecisionPrimitives.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw
$tokens=$null; $errors=$null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Runner parser failure' }
$mocks = @{
    'Wait-MarketBrainHealth' = 'function Wait-MarketBrainHealth { param($ServiceBaseUrl) }'
    'Resolve-LlamaCli' = 'function Resolve-LlamaCli { param($RequestedPath) return "OFFLINE-MOCK" }'
    'Invoke-LlamaCliProcess' = @'
function Invoke-LlamaCliProcess {
    param($ExecutablePath,$Arguments,$StandardOutputPath,$StandardErrorPath,$ProcessTimeoutSeconds,$StandardInputText)
    if ($Arguments[0] -eq '--help') {
        $stdout = '--single-turn --grammar-file --no-display-prompt --seed'
        $exitCode=0; $timedOut=$false
    } else {
        $env:MARKETBRAIN_OFFLINE_TEST_CALLS = [string](1 + [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS)
        $mockCall = (([int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS - 1) % 4) + 1
        $exitCode=0; $timedOut=$false
        $id = 'CANDIDATE_{0:D3}' -f $mockCall
        $payload = [ordered]@{candidateId=$id;decision='SHORTLIST';riskBucket='HIGH';trapDetected='NO';scoreBand='HIGH';confidenceBand='MEDIUM';primaryReasonCode='RECOVERY_SETUP'}
        if ($env:MARKETBRAIN_OFFLINE_CONTRAST_PASS -ne '1' -or [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS -gt 4) {
            if ($mockCall -eq 2) { $payload.Remove('riskBucket') }
            if ($mockCall -eq 3) { $exitCode=1 }
            if ($mockCall -eq 4) { $timedOut=$true; $exitCode=-999 }
        }
        $stdout = $payload | ConvertTo-Json -Compress
        $promptIndex=[array]::IndexOf($Arguments,'-f') + 1
        $echo=[IO.File]::ReadAllText($Arguments[$promptIndex]).Trim()
        $stdout="Loading model...`n> " + $echo.Substring(0,$echo.Length-4) + " ... (truncated)`n" + $stdout
    }
    $stdout | Set-Content -LiteralPath $StandardOutputPath -Encoding UTF8
    'offline stderr evidence' | Set-Content -LiteralPath $StandardErrorPath -Encoding UTF8
    [pscustomobject]@{exitCode=$exitCode;timedOut=$timedOut;stdout=$stdout;stderr='offline stderr evidence'}
}
'@
}
foreach ($name in $mocks.Keys) {
    $function = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name}, $true)
    if ($null -eq $function) { throw "Cannot replace $name; refusing to run test." }
    $source = $source.Replace($function.Extent.Text, $mocks[$name])
}
# The mocked runner never uses the .NET 7 process API; allow this logic test on Windows PowerShell too.
$source = $source.Replace('#Requires -Version 7.0', '# Offline mocked test')
function Invoke-RestMethod {
    param($Method,$Uri,$ContentType,$Body,$TimeoutSec)
    if ($env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER -eq '1') { return [pscustomobject]@{decisionContractVersion='OLD'} }
    $contrast = ($Body | ConvertFrom-Json).selectionMode -eq 'CONTRAST_VALIDATION'
    $candidates = @(1..4 | ForEach-Object {
        [pscustomobject]@{
            candidateId=('CANDIDATE_{0:D3}' -f $_); symbol="SYNTHETIC_$_"; independentPrompt="As-of fixture $_`n{factsVersion=TEST, unfinished map and tail"
            prompt='BASELINE MUST NOT BE SENT'; evidenceCategory='CAUTION'; hardExclusionReason='NONE'
            javaDecision='SHORTLIST'; javaRiskBucket='HIGH'; javaTrapDetected='YES'; javaScoreBand='HIGH'
            javaConfidenceBand='MEDIUM'; javaPrimaryReasonCode='RECOVERY_SETUP'; javaFeaturePriorScore=60
            javaQualityAnchorScore=59; javaQualityAnchorRank=$_; javaScoreCapHint='HARD_CAP_69'
            javaTopPickEligibility='CAUTION'; actualRank=$_; targetNetReturnPercent=10
            targetBenchmarkExcessReturnPercent=5; targetMaximumDrawdownPercent=3
            diagnosticExpectedDecisions=$(if ($contrast) { @('SHORTLIST') } else { @() })
        }
    })
    [pscustomobject]@{
        decisionContractVersion='MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5'; grammarVersion='GBNF_V1'
        datasetRunId='offline'; asOf='2026-06-05'; labelThrough='2026-09-08'; candidateCount=4; candidates=$candidates
        grammar="root ::= candidate-id`ncandidate-id ::= digit`ndigit ::= [0-9]"
        allowedDecisions=@('REJECT','WATCHLIST','SHORTLIST','TOP_PICK'); allowedRiskBuckets=@('LOW','MEDIUM','HIGH','BLOCKED')
        allowedTrapFlags=@('YES','NO'); allowedScoreBands=@('VERY_LOW','LOW','MEDIUM','HIGH','VERY_HIGH')
        allowedConfidenceBands=@('LOW','MEDIUM','HIGH'); allowedReasonCodes=@('RECOVERY_SETUP')
    }
}
try {
    $fixturePath = Join-Path $testDirectory 'MockRunner.ps1'
    $source | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1') -Destination $testDirectory
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS='0'
    $outputDirectory = Join-Path $testDirectory 'results'
    Write-Host '[0%] Running four synthetic subprocess results through the full runner...'
    & $fixturePath -DatasetRunId 'offline' -CandidateLimit 4 -OutputDirectory $outputDirectory
    $result = Get-ChildItem -LiteralPath $outputDirectory -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ($result.businessValidCount -ne 1 -or $result.schemaValidCount -ne 3 -or $result.llamaCppCallCount -ne 4 -or $result.decisionAlignedWithJavaCount -ne 1) {
        throw 'Missing keys, nonzero exits or timeouts were not evaluated correctly.'
    }
    if (-not $result.attempts[0].prompt.StartsWith('As-of fixture 1')) { throw 'Wrong prompt reached the runner.' }
    if (-not $result.attempts[0].extraction.echoRemoved) { throw 'Full runner did not remove echoed prompt.' }
    if (@(Get-ChildItem -LiteralPath $outputDirectory -File).Count -ne 2) { throw 'Expected only result and log.' }
    $env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER = '1'
    $oldDirectory = Join-Path $testDirectory 'old-server'
    $blocked=$false
    try { & $fixturePath -DatasetRunId 'offline' -OutputDirectory $oldDirectory }
    catch { $blocked = $_.Exception.Message -like '*V5 Java service*' }
    if (-not $blocked -or [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS -ne 4) { throw 'Old deployment was not blocked before inference.' }
    $failed = Get-ChildItem -LiteralPath $oldDirectory -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ($failed.status -ne 'FAILED' -or $failed.llamaCppCallCount -ne 0) { throw 'Failure evidence missing.' }
    Remove-Item Env:\MARKETBRAIN_OFFLINE_TEST_OLD_SERVER
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS='0'
    Copy-Item -LiteralPath $fixturePath -Destination (Join-Path $testDirectory 'PreviewPrototypeSwingTypedDecisionPrimitives.ps1')
    $comparisonSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ComparePrototypeSwingTypedDecisions.ps1') -Raw
    $comparisonPath = Join-Path $testDirectory 'MockComparison.ps1'
    $comparisonSource.Replace('#Requires -Version 7.0', '# Offline mocked test') | Set-Content -LiteralPath $comparisonPath -Encoding UTF8
    $comparisonOutput = Join-Path $testDirectory 'comparison-output'
    & $comparisonPath -DatasetRunId 'offline' -CandidateLimit 4 -ModelRefs @('test/model-a','test/model-b') -OutputDirectory $comparisonOutput
    $comparisonResult = Get-ChildItem -LiteralPath $comparisonOutput -Filter comparison.json -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ($comparisonResult.results.Count -ne 2 -or -not $comparisonResult.comparableInputs -or [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS -ne 8) {
        throw 'Sequential comparison or input parity failed.'
    }
    if (@(Get-ChildItem -LiteralPath $comparisonOutput -Recurse -File).Count -ne 2) {
        throw 'Comparison failed to consolidate evidence into two files.'
    }
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS='0'
    $gateOutput = Join-Path $testDirectory 'gate-blocked'
    & $comparisonPath -DatasetRunId 'offline' -CandidateLimit 4 -ModelRefs @('test/model-a') -IncludeContrastChecks -OutputDirectory $gateOutput
    $gate = Get-ChildItem -LiteralPath $gateOutput -Filter comparison.json -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ($gate.status -ne 'DIAGNOSTIC_GATE_BLOCKED' -or $gate.results.Count -ne 1 -or [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS -ne 4) {
        throw 'Diagnostic failure did not stop subsequent inference.'
    }
    if (@(Get-ChildItem -LiteralPath $gateOutput -Recurse -File).Count -ne 2) { throw 'Gate failure lost compact evidence.' }
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS='0'
    $env:MARKETBRAIN_OFFLINE_CONTRAST_PASS='1'
    $passOutput = Join-Path $testDirectory 'gate-passed'
    & $comparisonPath -DatasetRunId 'offline' -CandidateLimit 4 -ModelRefs @('test/model-a') -IncludeContrastChecks -OutputDirectory $passOutput
    $passedGate = Get-ChildItem -LiteralPath $passOutput -Filter comparison.json -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ($passedGate.contrastGateBlocked -or $passedGate.results.Count -ne 2 -or [int]$env:MARKETBRAIN_OFFLINE_TEST_CALLS -ne 8) {
        throw 'Successful contrast gate did not proceed to balanced validation.'
    }
    if ($passedGate.results[0].evaluation.diagnosticPassedCount -ne 4 -or $null -ne $passedGate.comparableInputs -or $passedGate.comparedRunPairCount -ne 0) { throw 'Incorrect diagnostic metrics or cross-scenario comparison.' }
    if ($gate.skippedStageCount -ne 1 -or $passedGate.skippedStageCount -ne 0) { throw 'Skipped stages not explicit.' }
    Write-Host '[95%] Checking frozen snapshot, local model path and sampling arguments...'
    $snapshot=Invoke-RestMethod -Body '{"selectionMode":"CONTRAST_VALIDATION"}'
    $snapshot | Add-Member selectionMode 'CONTRAST_VALIDATION'
    $snapshot | Add-Member rankingHorizonSessions 20
    $snapshot.candidates=@($snapshot.candidates[0]);$snapshot.candidateCount=1
    $snapshotPath=Join-Path $testDirectory 'snapshot.json'
    $snapshot | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
    $localModel=Join-Path $testDirectory 'model.gguf'
    'offline model placeholder' | Set-Content -LiteralPath $localModel
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS='0'
    # Fail HTTP if the snapshot path accidentally contacts the service.
    $env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER='1'
    $snapshotOutput=Join-Path $testDirectory 'snapshot-output'
    & $fixturePath -DatasetRunId offline -SelectionMode CONTRAST_VALIDATION -CandidateLimit 1 -SnapshotPath $snapshotPath -ModelPath $localModel -Temperature 0.2 -Seed 1729 -OutputDirectory $snapshotOutput
    $snapshotResult=Get-ChildItem -LiteralPath $snapshotOutput -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    $a=$snapshotResult.attempts[0]
    if ($a.temperature -ne 0.2 -or $a.seed -ne 1729 -or $a.invocationArguments[0] -ne '-m' -or
        $a.invocationArguments -notcontains '--seed' -or $snapshotResult.llamaCppCallCount -ne 1) { throw 'Snapshot sampling/local model invocation incorrect.' }
    Write-Host '[100%] Offline runner tests passed; no external services or models were invoked.'
}
finally {
    $env:MARKETBRAIN_OFFLINE_TEST_OLD_SERVER = $priorOldServer
    $env:MARKETBRAIN_OFFLINE_CONTRAST_PASS = $priorContrastPass
    $env:MARKETBRAIN_OFFLINE_TEST_CALLS = $priorCalls
    $resolved = (Resolve-Path -LiteralPath $testDirectory).Path
    if ((Split-Path -Leaf $resolved) -like 'marketbrain-runner-test-*' -and
        (Split-Path -Parent $resolved) -eq ([System.IO.Path]::GetTempPath().TrimEnd('\'))) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Continue
    }
}
