#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PostRecovery.Core.ps1')
function New-State {return @{instance=$null;sequence=0;progressSeconds=0;tlsStamp=$null;tlsSeconds=0;tlsObservations=0;readySince=$null;readySamples=0}}
function New-Sample($n){return [pscustomobject]@{installationId='ea8b91471cf048aa97a0f6b939b355c7';instanceId='fresh';ordersEnabled=$false;brokerReady=$false;sequence=$n;phase='TRANSPORT_READY';denialsVerified=$true;failure=$null;lastTlsObservation=@{observedUtc=[string]$n;exitCode=0;timedOut=$false;connectStatus=200;tlsVerifyCode=0}}}
$s=New-State
foreach($n in 0..45){$passed=Update-PostRecoverySample $s (New-Sample $n) ($n*2);if($passed -ne ($n -eq 45)){throw 'Duration acceptance failed'}}
foreach($case in @('stale','worker','scope','blocked','tls','loss','frozenTls')){
    $s=New-State;$v=New-Sample 1;$null=Update-PostRecoverySample $s $v 0
    $v=New-Sample 2;$seconds=2
    switch($case){
        'stale'{$v.sequence=1;$seconds=11}
        'worker'{$v.instanceId='other'}
        'scope'{$v.ordersEnabled=$true}
        'blocked'{$v.failure='FAIL';$v.phase='BLOCKED'}
        'tls'{$v.lastTlsObservation.exitCode=28}
        'loss'{$v.phase='CONNECTING'}
        'frozenTls'{$v.lastTlsObservation.observedUtc='1';$seconds=21}
    }
    $failed=$false;try{$null=Update-PostRecoverySample $s $v $seconds}catch{$failed=$_.Exception.Message -like 'RECOVERY_*'}
    if(-not $failed){throw "Invalid sample accepted: $case"}
}
$s=New-State;$v=New-Sample 1;$v.instanceId='8df248cef94f4b5baff3d672e0863e17'
if(Update-PostRecoverySample $s $v 10){throw 'Old worker accepted'}
$failed=$false;try{$null=Update-PostRecoverySample $s $v 46}catch{$failed=$_.Exception.Message -eq 'RECOVERY_START_TIMEOUT'}
if(-not $failed){throw 'Old worker never times out'}
Write-Host 'POST_RECOVERY_SAMPLES_PASSED: duration, seven rejection paths, old worker timeout.'

# Read-only mismatch retains evidence without relaxing the original acceptance gate.
function Get-Item {return @{Attributes=0}}
function Test-Path {return $false}
function Read-BoundedJson {return @{instanceId='changed';sequence=50;phase='TRANSPORT_READY';failure=$null;ordersEnabled=$false;brokerReady=$false}}
function Get-ScheduledTask {return @{State='Disabled';Settings=@{Enabled=$false}}}
$v=Get-PostRecoveryPreflight @{root='C:\fixture';work='C:\fixture';taskName='fixture'} @{hashes=@{}}
if($v.passed -or $v.failure -ne 'RECOVERY_POST_STATUS_DRIFT' -or $v.currentStatus.instanceId -ne 'changed' -or $v.currentTask.state -ne 'Disabled'){throw 'Mismatch evidence missing or acceptance weakened'}
Write-Host 'POST_RECOVERY_MISMATCH_EVIDENCE_PASSED'
