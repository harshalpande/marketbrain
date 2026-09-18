#Requires -Version 5.1
# Offline fixtures/mocks only. Does not inspect the local machine's jobs or models.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmDependencyReview.ps1')
$script:checks=0
function Assert-Dependency([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message};$script:checks++}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-dependency-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$jobDir=Join-Path $testRoot 'step70-ollama-jobs/11111111-1111-1111-1111-111111111111'
[void](New-Item -ItemType Directory -Path $jobDir)
$statusPath=Join-Path $jobDir 'status.json'
[IO.File]::WriteAllText($statusPath,'{"status":"RUNNING","jobId":"11111111-1111-1111-1111-111111111111","model":"ibm/granite4.1:8b SECRET_MARKER","errorMessage":"SECRET_MARKER"}')
$before=(Get-FileHash $statusPath).Hash
$scan=Get-LlmDependencyEvidence $testRoot
Assert-Dependency ($scan.records.Count -eq 1 -and $scan.records[0].requiresReview) 'Running job not flagged.'
Assert-Dependency ($scan.records[0].modelTokens[0] -eq 'granite') 'Model hint missing.'
Assert-Dependency (($scan | ConvertTo-Json -Depth 10) -notmatch 'SECRET_MARKER') 'Raw evidence leaked.'
Assert-Dependency ((Get-FileHash $statusPath).Hash -eq $before) 'Saved job modified.'
[IO.File]::WriteAllText($statusPath,'{"status":"COMPLETED"}')
$scan=Get-LlmDependencyEvidence $testRoot
Assert-Dependency (-not $scan.records[0].requiresReview) 'Terminal status misread.'
foreach ($terminalStatus in @('DIAGNOSTIC_GATE_BLOCKED','INCOMPARABLE_INPUTS')) {
    [IO.File]::WriteAllText($statusPath,('{"status":"'+$terminalStatus+'"}'))
    $scan=Get-LlmDependencyEvidence $testRoot
    Assert-Dependency ($scan.records[0].status -eq $terminalStatus -and -not $scan.records[0].requiresReview) 'Completed diagnostic mislabeled UNKNOWN.'
}
[IO.File]::WriteAllText($statusPath,'{"status":"SECRET_MARKER"}')
$scan=Get-LlmDependencyEvidence $testRoot
Assert-Dependency ($scan.records[0].status -eq 'UNKNOWN' -and $scan.records[0].requiresReview) 'Unknown state trusted.'
[IO.File]::WriteAllText($statusPath,'broken')
$scan=Get-LlmDependencyEvidence $testRoot
Assert-Dependency ($scan.partial -and $scan.accessOrParseErrors -eq 1) 'Parse error hidden.'
$scan=Get-LlmDependencyEvidence (Join-Path $testRoot 'missing')
Assert-Dependency ($scan.partial -and $scan.status -eq 'UNKNOWN_MISSING_DIRECTORY') 'Missing directory treated as idle.'
$scan=Get-LlmDependencyEvidence $testRoot 1
Assert-Dependency $scan.partial 'Entry limit not flagged.'
$outside=Join-Path $testRoot 'outside'
[void](New-Item -ItemType Directory -Path $outside)
[IO.File]::WriteAllText((Join-Path $outside 'sweep.json'),'{"status":"RUNNING"}')
[void](New-Item -ItemType Junction -Path (Join-Path $jobDir 'link') -Target $outside)
$scan=Get-LlmDependencyEvidence $testRoot
Assert-Dependency ($scan.skippedLinks -eq 1 -and $scan.partial) 'Junction followed.'
$rejected=$false
try {Get-LlmDependencyEvidence ([IO.Path]::GetPathRoot($testRoot)) | Out-Null} catch {$rejected=$true}
Assert-Dependency $rejected 'Drive root accepted.'
function Get-CimInstance {
    param($Namespace,$ClassName,$OperationTimeoutSec,$ErrorAction)
    Assert-Dependency ($Namespace -eq 'Root/Microsoft/Windows/TaskScheduler' -and $ClassName -eq 'MSFT_ScheduledTask' -and $OperationTimeoutSec -eq 10) 'Unbounded/unexpected CIM query.'
    [pscustomobject]@{TaskName='SECRET_MARKER';State=3;Actions=@([pscustomobject]@{Execute='pwsh.exe';Arguments='-File C:\marketbrain\run.ps1 -Password SECRET_MARKER';WorkingDirectory='C:\private'})}
    [pscustomobject]@{TaskName='unrelated';State=2;Actions=@()}
}
$tasks=Get-LlmDependencyTasks
Assert-Dependency ($tasks.inspectedCount -eq 2 -and $tasks.matches.Count -eq 1) 'Task matching failed.'
Assert-Dependency (($tasks | ConvertTo-Json -Depth 10) -notmatch 'SECRET_MARKER|private|Password') 'Task contents leaked.'
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    Assert-Dependency ($Uri -eq 'http://127.0.0.1:8080/actuator/health' -and $Method -eq 'Get' -and $TimeoutSec -eq 10 -and $MaximumRedirection -eq 0) 'Unexpected HTTP request.'
    [pscustomobject]@{status='UP';details='SECRET_MARKER'}
}
$health=Get-LlmDependencyHealth 'http://127.0.0.1:8080'
Assert-Dependency ($health.status -eq 'UP' -and ($health | ConvertTo-Json) -notmatch 'SECRET_MARKER') 'Health projection failed.'
# Real entrypoint with all machine collectors replaced in a separate temporary helper.
$ops=Join-Path $testRoot 'repo/ops/windows'
[void](New-Item -ItemType Directory -Path $ops)
foreach ($name in @('LlmCleanupInventory.ps1','LlmDependencyReview.ps1','GetSpareLlmDependencyReview.ps1')) {Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $ops $name)}
$mock=@'
function Get-LlmDependencyHealth { [pscustomobject]@{status='UP'} }
function Get-LlmDependencyProcesses { @() }
function Get-LlmInventoryOllama { throw 'SECRET_MARKER' }
function Get-LlmDependencyTasks { [pscustomobject]@{partial=$false;matches=@()} }
function Get-LlmDependencyEvidence { [pscustomobject]@{partial=$true;records=@()} }
function Get-LlmInventoryReferences { [pscustomobject]@{references=@()} }
'@
[IO.File]::AppendAllText((Join-Path $ops 'LlmDependencyReview.ps1'),[Environment]::NewLine+$mock)
$output=Join-Path $testRoot 'reports'
& (Join-Path $ops 'GetSpareLlmDependencyReview.ps1') -OutputDirectory $output -ReviewDirectory $testRoot
& (Join-Path $ops 'GetSpareLlmDependencyReview.ps1') -OutputDirectory $output -ReviewDirectory $testRoot
$reports=@(Get-ChildItem $output -Filter '*.json')
Assert-Dependency ($reports.Count -eq 2) 'Report names collided.'
foreach ($file in $reports) {
    $raw=[IO.File]::ReadAllText($file.FullName);$report=$raw | ConvertFrom-Json
    Assert-Dependency ($report.status -eq 'COMPLETED_REVIEW_REQUIRED' -and -not $report.cleanupAuthorized -and $report.clearance -eq 'NOT_CLEARED_REQUIRES_OPERATOR_REVIEW') 'False cleanup clearance.'
    Assert-Dependency ($report.sections.ollama.status -eq 'UNKNOWN') 'Failure not isolated.'
    Assert-Dependency ($report.events.Count -eq 6 -and $report.safety.inferenceCalls -eq 0 -and $report.safety.jobStatusApiCalls -eq 0) 'Progress/safety regression.'
    Assert-Dependency ($raw -notmatch 'SECRET_MARKER') 'Exception content leaked.'
}
# Inspect parameter AST defaults without executing scripts (comparison requires PS7).
foreach ($name in @('PreviewPrototypeSwingTypedDecisionPrimitives.ps1','ComparePrototypeSwingTypedDecisions.ps1')) {
    $errors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
    Assert-Dependency ($errors.Count -eq 0) 'Default script parse error.'
    $parameter=$ast.ParamBlock.Parameters | Where-Object {$_.Name.VariablePath.UserPath -in @('ModelRef','ModelRefs')}
    Assert-Dependency ($parameter.DefaultValue.Extent.Text -match 'Qwen2.5-1.5B' -and $parameter.DefaultValue.Extent.Text -notmatch '0.5B') 'Retired model still default.'
}
Write-Host "PASS: $script:checks offline assertions. Test fixtures retained at $testRoot"
