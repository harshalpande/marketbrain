#requires -Version 7.2
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmReviewedSshRecovery.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayScheduledProbe.ps1')
$e=Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/automation-signing-current-20261119.json') -Raw|ConvertFrom-Json
$original=$e.result.paytmObservation.gatewaySupervisor.localSigningProbe.fields|ConvertTo-Json -Depth 12
function Assert-PaytmAccountPath($p){$p}
function Read-PaytmHostJson($p,$limit){$script:receipt}
$count=0
foreach($case in @('pass','run','source','partial','scope','cleanup','worker','changed','exit')){
 $script:receipt=$original|ConvertFrom-Json
 switch($case){
  run {$receipt.runId='other'}
  source {$receipt.sourceHashes.'PaytmGatewayAccount.ps1'='BAD'}
  partial {$receipt.taskRemoved=$false}
  scope {$receipt.ordersEnabled=$true}
  cleanup {$receipt.cleanupFailure='FAILED'}
  worker {$receipt.worker.signingChecks=1}
  changed {$receipt.productionStateUnchanged=$false}
  exit {$receipt.lastTaskResult=1}
 }
 $failed=$false;try{$null=Assert-PaytmNativeReceipt 'fixture'}catch{$failed=$true}
 if($failed -ne ($case -ne 'pass')){throw "Receipt case failed: $case"};$count++
}
# Production snapshot rules use the accepted incident fields and a mocked owned task.
$g=$e.result.paytmObservation.gatewaySupervisor
function Get-PaytmHostContract {@{root='root';work='work';name='fixture'}}
function Get-PaytmOwnedHostTask($id){@{State=if($script:case -eq 'running'){'Running'}else{'Ready'}}}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) @{LastTaskResult=1;LastRunTime=[datetime]'2026-11-15'}}
function Assert-PaytmHostControl {}
function Read-PaytmTransportControl {'ENABLED'}
function Test-Path {param($LiteralPath) $false}
function Get-FileHash {param($LiteralPath,$ErrorAction) @{Hash='unchanged'}}
function Read-PaytmHostJson($p,$limit){$script:files[[IO.Path]::GetFileName($p)]}
foreach($case in @('pass','running','instance','sequence','control','identity')){
 $script:case=$case;$script:files=@{}
 foreach($p in $g.files.PSObject.Properties){$files[$p.Name]=$p.Value.fields|ConvertTo-Json -Depth 8|ConvertFrom-Json}
 switch($case){
  instance {$files['blocked.json'].instanceId='other'}
  sequence {$files['status.json'].sequence=12162}
  control {$files['control.json'].mode='STOP'}
  identity {$files['startup-failure.json'].installationId='other'}
 }
 $failed=$false;try{$null=Get-PaytmCurrentRecoverySnapshot}catch{$failed=$true}
 if($failed -ne ($case -ne 'pass')){throw "Snapshot case failed: $case"};$count++
}
Write-Host "PASS: $count current receipt and incident rejection rules"
