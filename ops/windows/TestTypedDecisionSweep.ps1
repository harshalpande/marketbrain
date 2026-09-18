# Offline tests: mocked candidate retrieval and inference; no external service, database or model calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1')
function Assert-Sweep([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-sweep-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$oldCalls=$env:MARKETBRAIN_SWEEP_TEST_CALLS
$oldFail=$env:MARKETBRAIN_SWEEP_TEST_ALL_FAIL
try {
    Write-Host '[0%] Checking bounded Cartesian product and prompt isolation...'
    $configs=@(New-SweepConfigurations @('POLICY_FIRST','FACTS_FIRST','POLICY_FIRST') @('NONE','CONSISTENCY') @(0,0.2) @(160))
    Assert-Sweep ($configs.Count -eq 8) 'Duplicate configurations were not deduplicated.'
    $fixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-fixtures/typed-decision-v4-echo-regression.json') -Raw | ConvertFrom-Json
    # Use captured evidence to construct input snapshots, while production always obtains the snapshot from Java.
    $fixture | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $temp 'fixture.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1') -Destination $temp
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PreviewPrototypeSwingTypedDecisionPrimitives.ps1') -Destination $temp
    $helper=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1') -Raw
    $helper += @'

function Get-SweepSnapshot {
    param($BaseUrl,$DatasetRunId,$SelectionMode,$StartOffset,$CandidateLimit,$Horizon)
    $capture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture.json') -Raw | ConvertFrom-Json
    $candidates=@($capture.attempts | ForEach-Object { $_.offlineCandidateEvidence })
    foreach ($c in $candidates) { $c.independentPrompt="POLICY`nAssess the following input, independently of any Java baseline:`ncandidateId=$($c.candidateId); facts=mock" }
    [pscustomobject]@{decisionContractVersion='MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5';datasetRunId=$DatasetRunId;selectionMode=$SelectionMode;rankingHorizonSessions=$Horizon;candidates=$candidates;candidateCount=4}
}
function Invoke-SweepCandidate([hashtable]$Parameters) {
    $env:MARKETBRAIN_SWEEP_TEST_CALLS=[string]([int]$env:MARKETBRAIN_SWEEP_TEST_CALLS+1)
    $input=Get-Content -LiteralPath $Parameters.SnapshotPath -Raw | ConvertFrom-Json
    $c=$input.candidates[0]
    $good=$Parameters.Temperature -gt 0
    $a=[pscustomobject]@{candidateId=$c.candidateId;symbol=$c.symbol;schemaValid=$true;businessValid=$good;diagnosticPassed=$good
        modelDecision='REJECT';modelRiskBucket='HIGH';modelTrapDetected='NO';modelScoreBand='LOW';modelConfidenceBand='LOW';modelPrimaryReasonCode='MIXED_EVIDENCE'
        hardExclusionReason=$c.hardExclusionReason;reasonEvidenceWarnings=@();elapsedMillis=20;prompt=$c.independentPrompt;temperature=$Parameters.Temperature;seed=$Parameters.Seed}
    if ($env:MARKETBRAIN_SWEEP_TEST_ALL_FAIL -eq '1') { $a.businessValid=$false;$a.diagnosticPassed=$false }
    $result=[pscustomobject]@{status='REVIEW_REQUIRED';attempts=@($a)}
    Save-TypedDecisionEvidence $result (Join-Path $Parameters.OutputDirectory 'mock.json')
    & $Parameters.Heartbeat
}
'@
    $helper | Set-Content -LiteralPath (Join-Path $temp 'TypedDecisionSweep.ps1') -Encoding UTF8
    $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RunTypedDecisionConfigurationSweep.ps1') -Raw
    $source.Replace('#Requires -Version 7.0','# Offline mocked runner') | Set-Content -LiteralPath (Join-Path $temp 'RunTypedDecisionConfigurationSweep.ps1') -Encoding UTF8
    'mock gguf' | Set-Content -LiteralPath (Join-Path $temp 'model.gguf')
    'mock exe' | Set-Content -LiteralPath (Join-Path $temp 'llama.exe')
    $script=Join-Path $temp 'RunTypedDecisionConfigurationSweep.ps1'
    $parameters=@{DatasetRunId='offline';ModelPath=(Join-Path $temp 'model.gguf');LlamaCliPath=(Join-Path $temp 'llama.exe');OutputDirectory=(Join-Path $temp 'runs')}
    $env:MARKETBRAIN_SWEEP_TEST_CALLS='0'
    Write-Host '[20%] Running 64 mocked calls; failures must not abort other configurations...'
    & $script @parameters
    $path=Get-ChildItem -LiteralPath $parameters.OutputDirectory -Filter sweep.json -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $report=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Sweep ($report.records.Count -eq 64 -and [int]$env:MARKETBRAIN_SWEEP_TEST_CALLS -eq 64) 'Incorrect call/task count.'
    Assert-Sweep ($report.topConfigurations.Count -eq 3 -and $report.status -eq 'COMPLETED_SCREENING') 'Top three selection failed.'
    Assert-Sweep (@($report.topConfigurations | Where-Object { $_.businessValidPercent -ne 100 }).Count -eq 0) 'Unsafe configurations were shortlisted.'
    Assert-Sweep ($report.progressPercent -eq 100 -and $report.snapshotHash) 'Missing progress or input identity.'
    foreach ($c in $report.configurations) {
        $prompt=New-SweepPrompt 'policy. Assess the following input, independently of any Java baseline: facts' $c
        Assert-Sweep ($prompt -notmatch 'javaDecision|actualRank|targetNetReturn') 'Expected-answer leakage.'
    }
    Write-Host '[50%] Simulating interrupted aggregate save; resume must reuse child checkpoints...'
    $report.records=@($report.records | Select-Object -First 62)
    $report.status='INTERRUPTED'
    Save-TypedDecisionEvidence $report $path
    & $script -ResumeDirectory (Split-Path -Parent $path)
    Assert-Sweep ([int]$env:MARKETBRAIN_SWEEP_TEST_CALLS -eq 64) 'Resume repeated completed inference.'
    $resumed=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Sweep ($resumed.records.Count -eq 64) 'Resume failed to restore checkpoints.'
    Write-Host '[60%] Reusing frozen top configurations for another selection mode...'
    $validationParams=$parameters.Clone();$validationParams.OutputDirectory=Join-Path $temp 'validation'
    & $script @validationParams -FinalistsFromDirectory (Split-Path -Parent $path) -SelectionMode BALANCED_VALIDATION
    $validationPath=Get-ChildItem -LiteralPath $validationParams.OutputDirectory -Filter sweep.json -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $validation=Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    Assert-Sweep ($validation.configurations.Count -eq 3 -and $validation.finalistSourceSha256) 'Frozen finalists were not reused.'
    Assert-Sweep ($validation.status -eq 'COMPLETED_VALIDATION_REVIEW_REQUIRED') 'Validation mislabeled as market readiness.'
    Write-Host '[65%] Verifying pinned model changes block resume...'
    'different model' | Set-Content -LiteralPath $parameters.ModelPath
    $blocked=$false; try { & $script -ResumeDirectory (Split-Path -Parent $path) } catch { $blocked=$_.Exception.Message -like '*Model or llama executable changed*' }
    Assert-Sweep $blocked 'Changed model was allowed to resume.'
    'mock gguf' | Set-Content -LiteralPath $parameters.ModelPath
    Write-Host '[75%] Verifying budget validation and explicit no-qualifier result...'
    $blocked=$false; try { & $script @parameters -MaxCalls 10 } catch { $blocked=$_.Exception.Message -like '*budget exceeded*' }
    Assert-Sweep $blocked 'Call budget was not enforced.'
    $env:MARKETBRAIN_SWEEP_TEST_ALL_FAIL='1'
    $parameters.OutputDirectory=Join-Path $temp 'failed'
    & $script @parameters -Layouts POLICY_FIRST -ExampleModes NONE -Temperatures 0
    $failedPath=Get-ChildItem -LiteralPath $parameters.OutputDirectory -Filter sweep.json -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $failed=Get-Content -LiteralPath $failedPath -Raw | ConvertFrom-Json
    Assert-Sweep ($failed.status -eq 'COMPLETED_NO_QUALIFIER' -and $failed.topConfigurations.Count -eq 0) 'Manufactured a winner from failures.'
    Write-Host '[100%] Sweep planning, ranking, persistence, resume and safety tests passed. No models invoked.'
} finally {
    $env:MARKETBRAIN_SWEEP_TEST_CALLS=$oldCalls
    $env:MARKETBRAIN_SWEEP_TEST_ALL_FAIL=$oldFail
    $resolved=[IO.Path]::GetFullPath($temp)
    if ((Split-Path -Parent $resolved) -eq ([IO.Path]::GetTempPath().TrimEnd('\')) -and (Split-Path -Leaf $resolved) -like 'marketbrain-sweep-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
