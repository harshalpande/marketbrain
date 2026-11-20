#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmDurableCollectorSetup.ps1')
. (Join-Path $PSScriptRoot 'PaytmDurableCollectorPreflight.ps1')
$receipt=(Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/durable-collector-install-20261120.json') -Raw|ConvertFrom-Json).installation
foreach($case in @('valid','wrongRun','started','enabled','wrongWorker','wrongHost','wrongXml','wrongSid','credentialFailed')){
 $r=$receipt|ConvertTo-Json -Depth 8|ConvertFrom-Json
 switch($case){
  wrongRun {$r.runId='0'*32}
  started {$r.workerStarted=$true}
  enabled {$r.disabledVerified=$false}
  wrongWorker {$r.workerSha256='A'*64}
  wrongHost {$r.knownHostsSha256='A'*64}
  wrongXml {$r.taskXmlSha256='A'*64}
  wrongSid {$r.credentialCheck.resolvedSid='S-1-5-18'}
  credentialFailed {$r.credentialCheck.accepted=$false}
 }
 $passed=$false;try{Assert-DurableCollectorReceipt $r;$passed=$true}catch{if($_.Exception.Message -notlike 'COLLECTOR_RECEIPT_*'){throw}}
 if($passed -ne ($case -eq 'valid')){throw "Receipt validation failed: $case"}
}
# Verify installed-file and control drift fail before any task or runtime action.
function Assert-TimeObservationAcl($Path){}
function Get-FileHash($LiteralPath){@{Hash=if($LiteralPath.EndsWith('worker.ps1')){if($script:case -eq 'fileDrift'){'A'*64}else{$receipt.workerSha256}}else{$receipt.knownHostsSha256}}}
function Read-TimeObservationFile($Path){@{version=1;installationId=$receipt.runId;enabled=($script:case -eq 'controlEnabled')}}
function Get-ScheduledTask {throw 'UNEXPECTED_TASK_ACCESS'}
foreach($script:case in @('fileDrift','controlEnabled')){
 $failure=$null;try{Get-DurableCollectorStagingPreflight $receipt}catch{$failure=$_.Exception.Message}
 $expected=if($case -eq 'fileDrift'){'COLLECTOR_INSTALLED_FILE_DRIFT'}else{'COLLECTOR_CONTROL_DRIFT'}
 if($failure -cne $expected){throw "Preflight failure mismatch: $case : $failure"}
}
Write-Host 'DURABLE_PREFLIGHT_VERIFIED: 9 receipt cases and 2 installed-state drift cases; read-only.'
