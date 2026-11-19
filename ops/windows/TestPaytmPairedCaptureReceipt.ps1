#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmPairedCaptureResume.ps1')
$original=Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/concurrent-tls-windows-20261119.json') -Raw
function Assert-PaytmAccountPath($p){$p}
function Read-PaytmHostJson($p,$limit){$script:receipt}
function Get-FileHash {param($LiteralPath) @{Hash=if($script:case -eq 'hash'){'WRONG'}else{'A4694E1AF2C9DA26EED3451EE3B771FD1635B34BC3F19911C5536BD7846C59A7'}}}
$count=0
foreach($case in @('pass','hash','run','failure','cleanup','account','lock','orders','transport','comparison','short','outage','incomplete')){
 $script:case=$case;$script:receipt=$original|ConvertFrom-Json
 switch($case){
  run {$receipt.runId='wrong'}
  failure {$receipt.failure='OTHER'}
  cleanup {$receipt.cleanupFailure='FAILED'}
  account {$receipt.accountPreserved=$false}
  lock {$receipt.finalApplicationLockVerified=$false}
  orders {$receipt.ordersEnabled=$true}
  transport {$receipt.nativeRecovery.first.denialsVerified=$false}
  comparison {$receipt.comparisonId='wrong'}
  short {$receipt.diagnostic.elapsedSeconds=299}
  outage {$receipt.diagnostic.outageSamples=1}
  incomplete {$receipt.diagnostic.captureCompleted=$false}
 }
 $failed=$false;try{$null=Assert-PaytmNativeReceipt 'fixture'}catch{$failed=$true}
 if($failed -ne ($case -ne 'pass')){throw "Receipt case failed: $case"};$count++
}
Write-Host "PASS: $count concurrent capture receipt cases"
