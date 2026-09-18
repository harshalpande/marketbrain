#Requires -Version 5.1
# All destructive HTTP calls mocked; filesystem moves affect tiny dedicated temp fixtures only.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ApprovedLlmCleanup.ps1')
$script:checks=0
function Assert-CleanupTest([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message};$script:checks++}
function Assert-CleanupThrows([scriptblock]$Action) {$failed=$false;try {& $Action | Out-Null} catch {$failed=$true};Assert-CleanupTest $failed 'Expected cleanup guard failure.'}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-cleanup-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
Assert-CleanupThrows {Assert-CleanupPath '.'}
Assert-CleanupThrows {Assert-CleanupPath 'C:\'}
Assert-CleanupThrows {Assert-CleanupPath '\\host\share\file'}
Assert-CleanupThrows {Get-ApprovedCleanupPlan $testRoot 'invalid'}
$outside=Join-Path $testRoot 'outside';[void](New-Item -ItemType Directory -Path $outside)
$linked=Join-Path $testRoot 'link';[void](New-Item -ItemType Junction -Path $linked -Target $outside)
Assert-CleanupThrows {Assert-CleanupPath (Join-Path $linked 'absent.gguf')}
$plan=[pscustomobject]@{granite='ibm/granite4.1:8b';graniteDigest='expected';oldFile=(Join-Path $testRoot 'old.gguf');retainedFile=(Join-Path $testRoot 'keep.gguf');quarantineFile=(Join-Path $testRoot 'quarantine/old.gguf');oldExpectedBytes=3;retainedExpectedBytes=4}
[IO.File]::WriteAllText($plan.oldFile,'old');[IO.File]::WriteAllText($plan.retainedFile,'keep')
$evidence=Get-CleanupFileEvidence $plan.oldFile 3
Assert-CleanupThrows {Get-CleanupFileEvidence $plan.oldFile 4}
Move-ApprovedQwenFile $plan $evidence
Assert-CleanupTest ((Test-Path $plan.quarantineFile) -and -not (Test-Path $plan.oldFile)) 'Single file not quarantined.'
Assert-CleanupTest ((Get-FileHash $plan.quarantineFile).Hash -eq $evidence.sha256) 'Quarantine content changed.'
Assert-CleanupTest ((Get-Content $plan.retainedFile -Raw) -eq 'keep') 'Retained fixture touched.'
Assert-CleanupThrows {Move-ApprovedQwenFile $plan $evidence}
Assert-CleanupThrows {Assert-GraniteIdentity ([pscustomobject]@{models=@([pscustomobject]@{name=$plan.granite;digest='changed'})}) $plan}
Assert-CleanupTest (-not (Assert-GraniteIdentity ([pscustomobject]@{models=@()}) $plan)) 'Absent model not idempotent.'
# Direct API contract test: only the exact documented DELETE is allowed.
$script:deleteCalls=0
function Invoke-RestMethod {
    param($Uri,$Method,$ContentType,$Body,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    Assert-CleanupTest ($Uri -eq 'http://127.0.0.1:11434/api/delete' -and $Method -eq 'Delete') 'Wrong deletion endpoint.'
    Assert-CleanupTest (($Body | ConvertFrom-Json).model -eq 'ibm/granite4.1:8b' -and $TimeoutSec -eq 120 -and $MaximumRedirection -eq 0) 'Wrong deletion contract.'
    $script:deleteCalls++
}
Remove-ApprovedGranite
Assert-CleanupTest ($script:deleteCalls -eq 1) 'Deletion API not invoked through mock.'
# Snapshot guards never touch actual processes/APIs.
$script:loaded=$true;$script:apiAvailable=$true;$script:processActive=$false;$script:healthUp=$true
function Get-LlmInventoryOllama {
    [pscustomobject]@{endpoint='/api/tags';status=if($script:apiAvailable){'AVAILABLE'}else{'UNKNOWN'};models=@()}
    [pscustomobject]@{endpoint='/api/ps';status='AVAILABLE';models=if($script:loaded){@([pscustomobject]@{name='any';digest='d'})}else{@()}}
}
function Get-Process {param($ErrorAction);if($script:processActive){[pscustomobject]@{ProcessName='llama-server'}}}
function Get-LlmDependencyHealth {if($script:healthUp){[pscustomobject]@{status='UP'}}else{[pscustomobject]@{status='DOWN'}}}
Assert-CleanupThrows {Get-CleanupSnapshot}
$script:loaded=$false;$script:apiAvailable=$false
Assert-CleanupThrows {Get-CleanupSnapshot}
$script:apiAvailable=$true;$script:processActive=$true
Assert-CleanupThrows {Get-CleanupSnapshot}
$script:processActive=$false;$script:healthUp=$false
Assert-CleanupThrows {Get-CleanupSnapshot}
# Orchestration uses an in-memory model registry and fixture files only.
$script:registry=@([pscustomobject]@{name=$plan.granite;digest='expected'},[pscustomobject]@{name='other';digest='retain'})
function Get-CleanupSnapshot {[pscustomobject]@{models=$script:registry;health='UP';cDriveFreeBytes=100}}
function Test-Path {
    param($LiteralPath,$PathType)
    if ($LiteralPath -in @('C:\MarketBrainTools\llama.cpp\llama-cli.exe','C:\MarketBrainTools\llama.cpp\llama-server.exe')) {return $true}
    if ($PathType) {Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType} else {Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
}
function Remove-ApprovedGranite {$script:deleteCalls++;$script:registry=@($script:registry | Where-Object name -ne 'ibm/granite4.1:8b')}
function New-TestCleanupReport {[pscustomobject]@{updatedAtUtc=$null;status='STARTING';before=$null;after=$null;retainedBefore=$null;retainedAfter=$null;oldFileBefore=$null;quarantineState='NOT_ATTEMPTED';graniteState='NOT_ATTEMPTED';observedCDriveFreeDeltaBytes=$null}}
$plan.oldFile=Join-Path $testRoot 'old2.gguf';$plan.quarantineFile=Join-Path $testRoot 'quarantine/old2.gguf'
[IO.File]::WriteAllText($plan.oldFile,'old')
$checkpoint={param($percent,$message);Save-LlmInventoryReport $report (Join-Path $testRoot 'report.json')}
$report=New-TestCleanupReport
Assert-CleanupThrows {Invoke-ApprovedCleanup $plan $report $checkpoint $true $false}
$report=New-TestCleanupReport;$countBefore=$script:deleteCalls
Invoke-ApprovedCleanup $plan $report $checkpoint $false $false
Assert-CleanupTest ($report.status -eq 'PREVIEW_ONLY' -and $script:deleteCalls -eq $countBefore -and (Test-Path -LiteralPath $plan.oldFile)) 'Preview mutated targets.'
$report=New-TestCleanupReport
Invoke-ApprovedCleanup $plan $report $checkpoint $true $true
Assert-CleanupTest ($report.status -eq 'COMPLETED_SCOPED_CLEANUP_REVIEW_REQUIRED' -and $report.quarantineState -eq 'VERIFIED') 'Apply failed.'
Assert-CleanupTest ($report.retainedAfter.sha256 -eq $report.retainedBefore.sha256 -and $script:registry.Count -eq 1 -and $script:registry[0].name -eq 'other') 'Retained model changed.'
$report=New-TestCleanupReport;$countBefore=$script:deleteCalls
$plan.quarantineFile=Join-Path $testRoot 'quarantine/another-run.gguf'
Invoke-ApprovedCleanup $plan $report $checkpoint $true $true
Assert-CleanupTest ($script:deleteCalls -eq $countBefore -and $report.graniteState -eq 'ALREADY_ABSENT_NOT_REMOVED_BY_THIS_RUN') 'Rerun re-deleted model.'
# Timeout/unknown DELETE result must retain intent, never pretend rollback/completion.
$plan.quarantineFile=Join-Path $testRoot 'quarantine/unused.gguf'
$script:registry=@([pscustomobject]@{name=$plan.granite;digest='expected'})
function Remove-ApprovedGranite {throw 'Simulated timeout'}
$report=New-TestCleanupReport
Assert-CleanupThrows {Invoke-ApprovedCleanup $plan $report $checkpoint $true $true}
Assert-CleanupTest ($report.graniteState -eq 'DELETE_REQUEST_INTENT_RECORDED' -and $report.status -ne 'COMPLETED_SCOPED_CLEANUP_REVIEW_REQUIRED') 'Ambiguous deletion lost intent.'
# Evidence persistence failure must stop before any mutation.
$plan.oldFile=Join-Path $testRoot 'old3.gguf'
[IO.File]::WriteAllText($plan.oldFile,'old')
$report=New-TestCleanupReport
Assert-CleanupThrows {Invoke-ApprovedCleanup $plan $report {throw 'Simulated disk full'} $true $true}
Assert-CleanupTest ((Test-Path -LiteralPath $plan.oldFile) -and $report.graniteState -eq 'NOT_ATTEMPTED') 'Continued despite failed checkpoint.'
$script:registry=@([pscustomobject]@{name=$plan.granite;digest='changed'})
$report=New-TestCleanupReport
Assert-CleanupThrows {Invoke-ApprovedCleanup $plan $report $checkpoint $true $true}
Assert-CleanupTest (Test-Path -LiteralPath $plan.oldFile) 'Identity guard allowed quarantine.'
$script:registry=@([pscustomobject]@{name=$plan.granite;digest='expected'})
function Remove-ApprovedGranite {$script:registry=@();[IO.File]::WriteAllText($plan.retainedFile,'oops')}
$report=New-TestCleanupReport
Assert-CleanupThrows {Invoke-ApprovedCleanup $plan $report $checkpoint $true $true}
Assert-CleanupTest ($report.status -ne 'COMPLETED_SCOPED_CLEANUP_REVIEW_REQUIRED') 'Retained hash mismatch accepted.'
Write-Host "PASS: $script:checks offline cleanup assertions; fixture directory retained: $testRoot"
