#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
function Get-PaytmHostContract {@{work='fixture';name='fixture'}}
function Get-PaytmOwnedHostTask {@{State='Running'}}
function Test-Path {param($LiteralPath) $false}
function Assert-PaytmManagedStatus {}
function Read-PaytmHostJson {
 if($case -eq 'missing'){throw [IO.FileNotFoundException]::new()}
 @{installationId='fixture';instanceId='a';phase=$(if($case -eq 'backoff'){'BACKOFF'}else{'TRANSPORT_READY'});sequence=1;childProcessId=1}
}
foreach($case in @('backoff','stale','missing')){
 $message=$null
 try{Wait-PaytmManagedHost fixture TRANSPORT_READY -TimeoutSeconds 1}catch{$message=$_.Exception.Message}
 $expected=if($case -eq 'backoff'){'TRANSPORT_REQUESTED_STATE_TIMEOUT'}else{'TRANSPORT_HEARTBEAT_TIMEOUT'}
 if($message -cne $expected){throw "WRONG_TIMEOUT_CLASSIFICATION_$case"}
}
Write-Progress -Activity 'Managed Windows transport' -Completed
Write-Host 'PASS: three timeout classifications; readiness differs from heartbeat.'
