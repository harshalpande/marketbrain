# Offline mocked diagnostic regression. No real model, Java, database or broker calls.
param([string]$SourceSweepPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionDiagnostics.ps1')
function Assert-Diagnostic([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$directory=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-diagnostic-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$previousCalls=$env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS
try {
    if ($SourceSweepPath) {
        $capturedSweep=ConvertFrom-SweepJson (Get-Content -LiteralPath $SourceSweepPath -Raw)
        Assert-Diagnostic ($capturedSweep.snapshotHash -eq (Get-SweepHash $capturedSweep.snapshot)) 'Captured sweep snapshot hash changed under this PowerShell version.'
        $inputCount=0
        foreach ($c in $capturedSweep.snapshot.candidates) { foreach ($arm in (Get-DecisionDiagnosticArms)) {
            $inputCase=New-DecisionDiagnosticInput $c $arm $capturedSweep.snapshot.grammar
            Assert-Diagnostic (-not [string]::IsNullOrWhiteSpace($inputCase.prompt)) 'Captured diagnostic prompt is empty.'
            $inputCount++
        } }
        Assert-Diagnostic ($inputCount -eq 20) 'Expected twenty captured diagnostic inputs.'
        Write-Host 'Captured source fingerprint and twenty inputs verified; no inference.'
    }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host '[5%] Checking native process argument isolation, closed stdin, stderr and timeout (no model)...'
        $runtime=(Get-Process -Id $PID).Path
        $previousOverride=$env:LLAMA_ARG_DIAGNOSTIC_TEST
        try {
            $env:LLAMA_ARG_DIAGNOSTIC_TEST='must not reach child'
            $probe=Invoke-DecisionDiagnosticProcess $runtime @('-NoProfile','-Command','if ($env:LLAMA_ARG_DIAGNOSTIC_TEST) { exit 99 }; if ([Console]::In.ReadToEnd() -ne "") { exit 98 }; [Console]::Out.Write("argument with spaces"); [Console]::Error.Write("diagnostic stderr"); exit 7') 20 $null
            Assert-Diagnostic ($probe.exitCode -eq 7 -and $probe.stdout -eq 'argument with spaces' -and $probe.stderr -eq 'diagnostic stderr') 'Process redirection or argument isolation failed.'
            Assert-Diagnostic ($probe.clearedEnvironmentNames -contains 'LLAMA_ARG_DIAGNOSTIC_TEST' -and $env:LLAMA_ARG_DIAGNOSTIC_TEST -eq 'must not reach child') 'Child environment isolation modified parent or missed override.'
            $timeout=Invoke-DecisionDiagnosticProcess $runtime @('-NoProfile','-Command','Start-Sleep -Seconds 20') 1 $null
            Assert-Diagnostic ($timeout.timedOut -and $timeout.exitCode -eq -999 -and $timeout.elapsedSeconds -lt 10) 'Process timeout was not bounded.'
        } finally { $env:LLAMA_ARG_DIAGNOSTIC_TEST=$previousOverride }
    }
    Write-Host '[10%] Checking paired prompts, arguments, grammar and strict one-field validation...'
    $capture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-fixtures/typed-decision-v4-echo-regression.json') -Raw | ConvertFrom-Json
    $cases=@($capture.attempts | ForEach-Object offlineCandidateEvidence)
    foreach ($c in $cases) {
        $c.independentPrompt="Return one JSON research assessment, not a trade order. Policy=TYPED_POLICY_V3; horizon=20 sessions.`nFields: candidateId, decision, riskBucket, trapDetected, scoreBand, confidenceBand, primaryReasonCode.`nAssess the following input, independently of any Java baseline:`ncandidateId=$($c.candidateId); facts=offline.`nReturn the seven fields only. Keep decision, risk and score consistent."
    }
    $grammar=@'
root ::= candidate-id decision
candidate-id ::= "\"CANDIDATE_001\""
decision ::= "\"REJECT\"" | "\"WATCHLIST\"" | "\"SHORTLIST\"" | "\"TOP_PICK\""
'@
    $arms=@(Get-DecisionDiagnosticArms)
    Assert-Diagnostic ($arms.Count -eq 5) 'Expected five fixed diagnostic arms.'
    foreach ($c in $cases) {
        $seven=New-DecisionDiagnosticInput $c $arms[0] $grammar
        $free=New-DecisionDiagnosticInput $c $arms[1] $grammar
        $one=New-DecisionDiagnosticInput $c $arms[2] $grammar
        $oneFree=New-DecisionDiagnosticInput $c $arms[3] $grammar
        Assert-Diagnostic ($seven.prompt -ceq $free.prompt -and $one.prompt -ceq $oneFree.prompt) 'Grammar comparison changed prompt.'
        Assert-Diagnostic ($null -eq $free.grammar -and $null -eq $oneFree.grammar) 'Free arm retained grammar.'
        Assert-Diagnostic ($one.prompt -notmatch 'Return the seven|Fields: candidateId|javaDecision=|actualRank=') 'Wrong one-field prompt or answer leakage.'
        Assert-Diagnostic ($one.grammar -notmatch 'candidate-id|riskBucket') 'One-field grammar has extra fields.'
        $c.javaDecision='SENTINEL_NOT_SENT';$c.javaScoreBand='SENTINEL_NOT_SENT'
        Assert-Diagnostic ((New-DecisionDiagnosticInput $c $arms[0] $grammar).prompt -ceq $seven.prompt) 'Java baseline leaked into prompt.'
    }
    foreach ($arm in $arms) {
        $values=@(Get-DecisionDiagnosticArguments $arm 'C:\model with spaces.gguf' $directory)
        Assert-Diagnostic (($values -contains '--grammar-file') -eq $arm.constrained) 'Wrong grammar arguments.'
        Assert-Diagnostic (($values -contains '--chat-template') -eq ($arm.template -eq 'chatml')) 'Template comparison not isolated.'
        Assert-Diagnostic ($values -contains 'C:\model with spaces.gguf' -and $values -contains '--single-turn' -and $values -contains '--offline') 'Unsafe/missing process arguments.'
    }
    $process=[pscustomobject]@{exitCode=0;timedOut=$false}
    $prompt='diagnostic test'
    $prefix="User:`n$prompt`n`nAssistant:`n"
    $valid=Test-DecisionDiagnosticResponse $cases[0] $arms[2] $prompt ($prefix+'{"decision":"SHORTLIST"}') $process
    Assert-Diagnostic ($valid.decisionCorrect -and $null -eq $valid.businessValid -and $null -eq $valid.fullDiagnosticPassed) 'Single-field result mislabeled as full policy pass.'
    foreach ($bad in @('{"decision":"SHORTLIST","decision":"REJECT"}','{"decision":"SHORTLIST","extra":1}','[{"decision":"SHORTLIST"}]','{"decision":"SHORTLIST"} explanation','{"decision":"SHORTLIST"}{"decision":"REJECT"}')) {
        Assert-Diagnostic (-not (Test-DecisionDiagnosticResponse $cases[0] $arms[2] $prompt ($prefix+$bad) $process).schemaValid) 'Malformed one-field response accepted.'
    }
    Assert-Diagnostic (-not (Test-DecisionDiagnosticResponse $cases[0] $arms[2] $prompt '{"decision":"SHORTLIST"}' $process).decisionCorrect) 'Unverified input echo passed.'
    $process.timedOut=$true
    Assert-Diagnostic (-not (Test-DecisionDiagnosticResponse $cases[0] $arms[2] $prompt ($prefix+'{"decision":"SHORTLIST"}') $process).decisionCorrect) 'Timeout passed.'
    foreach ($file in @('TypedDecisionEvaluation.ps1','TypedDecisionSweep.ps1','TypedDecisionDiagnostics.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $directory }
    # Override only process launching in a temporary helper copy. Production file is unchanged.
    $helper=Get-Content -LiteralPath (Join-Path $directory 'TypedDecisionDiagnostics.ps1') -Raw
    $helper+=@'

function Invoke-DecisionDiagnosticProcess($Executable,$Arguments,$TimeoutSeconds,$Heartbeat) {
    if ($Arguments[0] -eq '--help') {
        return [pscustomobject]@{exitCode=0;timedOut=$false;stdout='--single-turn --grammar-file --seed --ctx-size --no-escape --offline --perf --log-verbosity --log-prompts-dir --output-file --chat-template chatml --no-display-prompt';stderr='';elapsedSeconds=0;clearedEnvironmentNames=@()}
    }
    $env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS=[string](1+[int]$env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS)
    $promptPath=$Arguments[[array]::IndexOf($Arguments,'-f')+1]
    $prompt=[IO.File]::ReadAllText($promptPath)
    $conversationPath=$Arguments[[array]::IndexOf($Arguments,'--output-file')+1]
    $id=[regex]::Match($prompt,'candidateId=(CANDIDATE_\d{3})').Groups[1].Value
    $choice=@{CANDIDATE_001='SHORTLIST';CANDIDATE_002='REJECT';CANDIDATE_003='WATCHLIST';CANDIDATE_004='REJECT'}[$id]
    $answer=if ($prompt.Contains('Output exactly one JSON field')) { @{decision=$choice}|ConvertTo-Json -Compress } else {
        @{candidateId=$id;decision='REJECT';riskBucket='HIGH';trapDetected='NO';scoreBand='VERY_HIGH';confidenceBand='HIGH';primaryReasonCode='WEAK_TREND'}|ConvertTo-Json -Compress
    }
    [IO.File]::WriteAllText($conversationPath,"User:`n$prompt`n`nAssistant:`n$answer`n")
    & $Heartbeat
    [pscustomobject]@{exitCode=0;timedOut=$false;stdout='mock';stderr='n_ctx = 4096';elapsedSeconds=0.01;clearedEnvironmentNames=@()}
}
'@
    Set-Content -LiteralPath (Join-Path $directory 'TypedDecisionDiagnostics.ps1') -Value $helper -Encoding UTF8
    $runner=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RunTypedDecisionCommunicationDiagnostics.ps1') -Raw
    $runner.Replace('#Requires -Version 7.0','# Offline test runner') | Set-Content -LiteralPath (Join-Path $directory 'RunTypedDecisionCommunicationDiagnostics.ps1') -Encoding UTF8
    'mock model' | Set-Content -LiteralPath (Join-Path $directory 'model.gguf')
    'mock exe' | Set-Content -LiteralPath (Join-Path $directory 'llama.exe')
    $snapshot=[pscustomobject]@{decisionContractVersion='MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5';selectionMode='CONTRAST_VALIDATION';candidates=$cases;grammar=$grammar}
    $source=[pscustomobject]@{version='TYPED_SWEEP_V1';status='COMPLETED_NO_QUALIFIER';snapshot=$snapshot;snapshotHash=(Get-SweepHash $snapshot)
        settings=@{modelPath=(Join-Path $directory 'model.gguf');llamaCliPath=(Join-Path $directory 'llama.exe');modelRef='offline'}
        modelSha256=(Get-FileHash -LiteralPath (Join-Path $directory 'model.gguf')).Hash;llamaSha256=(Get-FileHash -LiteralPath (Join-Path $directory 'llama.exe')).Hash}
    $sourcePath=Join-Path $directory 'source.json';Save-TypedDecisionEvidence $source $sourcePath
    $sourceHash=(Get-FileHash -LiteralPath $sourcePath).Hash
    $env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS='0'
    $script=Join-Path $directory 'RunTypedDecisionCommunicationDiagnostics.ps1'
    Write-Host '[40%] Running twenty mocked calls; failures stay in the report...'
    & $script -SourceSweepPath $sourcePath -OutputDirectory (Join-Path $directory 'runs')
    $resultPath=Get-ChildItem -LiteralPath (Join-Path $directory 'runs') -Filter diagnostics.json -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $result=ConvertFrom-SweepJson (Get-Content -LiteralPath $resultPath -Raw)
    Assert-Diagnostic ($result.records.Count -eq 20 -and $result.startedInvocationCount -eq 20 -and [int]$env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS -eq 20) 'Wrong bounded call count.'
    Assert-Diagnostic ($result.status -eq 'COMPLETED_DIAGNOSTIC_REVIEW_REQUIRED' -and -not $result.actionExecutionEnabled) 'Unsafe completion status.'
    $oneSummary=@($result.summary | Where-Object armId -eq ONE_GBNF_AUTO)[0]
    Assert-Diagnostic ($oneSummary.decisionCorrectCount -eq 4 -and $null -eq $oneSummary.fullDiagnosticPassedCount) 'Incorrect one-field metric.'
    Assert-Diagnostic ((Get-FileHash -LiteralPath $sourcePath).Hash -eq $sourceHash) 'Source sweep mutated.'
    Write-Host '[75%] Recovering child evidence without repeating model calls...'
    $result.records=@($result.records|Select-Object -First 18);$result.status='INTERRUPTED';$result.startedInvocationCount=24
    Save-TypedDecisionEvidence $result $resultPath
    & $script -ResumeDirectory (Split-Path -Parent $resultPath)
    Assert-Diagnostic ([int]$env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS -eq 20) 'Resume repeated completed inference.'
    $result=ConvertFrom-SweepJson (Get-Content -LiteralPath $resultPath -Raw)
    Assert-Diagnostic ($result.records.Count -eq 20) 'Recovery incomplete.'
    $savedHash=(Get-FileHash -LiteralPath $resultPath).Hash
    'changed model' | Set-Content -LiteralPath (Join-Path $directory 'model.gguf')
    $blocked=$false;try { & $script -ResumeDirectory (Split-Path -Parent $resultPath) } catch { $blocked=$_.Exception.Message -like '*Model or executable differs*' }
    Assert-Diagnostic ($blocked -and (Get-FileHash -LiteralPath $resultPath).Hash -eq $savedHash) 'Changed model resumed or altered saved evidence.'
    Write-Host '[100%] Diagnostic pairing, validation, bounded orchestration and resume tests passed. No models invoked.'
} finally {
    $env:MARKETBRAIN_DIAGNOSTIC_TEST_CALLS=$previousCalls
    $resolved=[IO.Path]::GetFullPath($directory)
    if ((Split-Path -Parent $resolved) -eq ([IO.Path]::GetTempPath().TrimEnd('\')) -and (Split-Path -Leaf $resolved) -like 'marketbrain-diagnostic-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
