#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmConcurrentTlsRecovery.ps1')
$original=Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/recovery-tls-timeout-20261119.json') -Raw
function Assert-PaytmAccountPath($p){$p}
function Read-PaytmHostJson($p,$limit){$script:receipt}
function Get-FileHash {param($LiteralPath) @{Hash=if($script:case -eq 'hash'){'WRONG'}else{'7D408AD8C52172E568A77ED796599951993E0D5622BCF03D469CF8772CF7E17D'}}}
$count=0
foreach($case in @('pass','hash','run','failure','cleanup','account','lock','orders','transport')){
 $script:case=$case;$script:receipt=$original|ConvertFrom-Json
 switch($case){
  run {$receipt.runId='wrong'}
  failure {$receipt.failure='OTHER'}
  cleanup {$receipt.cleanupFailure='FAILED'}
  account {$receipt.accountPreserved=$false}
  lock {$receipt.finalApplicationLockVerified=$false}
  orders {$receipt.ordersEnabled=$true}
  transport {$receipt.nativeRecovery.first.denialsVerified=$false}
 }
 $failed=$false;try{$null=Assert-PaytmNativeReceipt 'fixture'}catch{$failed=$true}
 if($failed -ne ($case -ne 'pass')){throw "Receipt case failed: $case"};$count++
}
Write-Host "PASS: $count concurrent capture receipt cases"
