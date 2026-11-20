#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmCollectorRecovery.ps1')
function Start-Sleep {param($Seconds) if($Seconds -notin @(2,4,5,8)){throw 'UNBOUNDED_SLEEP'}}
function Get-CollectorRecoveryElapsed {if($script:case -eq 'expired'){301}else{1}}
function Test-CollectorApplicationReady {$script:readyCalls++;if($script:case -in @('down','expired','cancelDown')){return $false};return (-not ($script:case -eq 'outage' -and $script:readyCalls -eq 2))}
function Get-CollectorRecoveryBoot {if($script:case -in @('boot','auth','badBoot') -or ($script:case -eq 'outage' -and $script:readyCalls -ge 3)){'new'}else{'old'}}
function Test-HealthTokenAuthority {$script:authCalls++;if($script:case -eq 'auth'){throw 'HEALTH_TOKEN_HTTP_FAILED'};if($script:case -eq 'badBoot'){'different'}else{'new'}}
function Invoke-CollectorCycle {param($Token,$SshArguments,$Boot,[switch]$Revoke)
 if($Revoke){$script:revokes++;return @{revoked=($script:case -notin @('down','unconfirmed'))}}
 $script:cycles++;$script:boots+=,$Boot
 if($script:case -eq 'exception'){throw 'DO_NOT_EXPORT_SECRET'}
 return @{accepted=($script:case -ne 'tls');healthySubmitted=($script:case -ne 'tls');failedPhase='PROXY_TLS';findings=@('GATEWAY_TLS_UNCONFIRMED','DO NOT EXPORT SECRET')}
}
foreach($script:case in @('healthy','outage','boot','auth','badBoot','tls','exception','down','expired','cancelDown','unconfirmed','saveFailure')){
 $script:readyCalls=0;$script:authCalls=0;$script:cycles=0;$script:revokes=0;$script:boots=@();$script:reads=0;$script:saved=@()
 $enabled={$script:reads++;return ($script:reads -le 4)}
 $save={param($v) if($script:case -eq 'saveFailure' -and $v.phase -ne 'FAILED'){throw 'write failure'};$script:saved+=,($v|ConvertTo-Json -Depth 6|ConvertFrom-Json)}
 $r=Invoke-CollectorRecoveryLoop 'SECRET_TOKEN' @() 'old' $enabled $save
 $ok=$case -in @('healthy','outage','boot','cancelDown')
 if(($r.phase -eq 'STOPPED') -ne $ok){throw ('RECOVERY_CASE_'+$case)}
 if(($r|ConvertTo-Json -Depth 6) -match 'SECRET_TOKEN|DO_NOT_EXPORT_SECRET|DO NOT EXPORT SECRET'){throw 'SECRET_EXPORTED'}
 if($case -in @('tls','exception','auth','badBoot') -and ($r.consecutiveFailures -ne 3 -or $r.failure -ne 'COLLECTOR_FAILURE_LIMIT')){throw 'FAILURE_LIMIT_CHANGED'}
 if($case -eq 'outage' -and ($r.recoveryCount -ne 1 -or $authCalls -ne 1 -or $boots[-1] -ne 'new' -or @($saved|Where-Object phase -eq 'WAITING_FOR_APPLICATION').Count -ne 1)){throw 'OUTAGE_RECOVERY_FAILED'}
 if($case -in @('down','expired','cancelDown') -and $cycles){throw 'PUBLISHED_DURING_OUTAGE'}
 if($case -eq 'expired' -and $r.failure -ne 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'){throw 'WAIT_NOT_BOUNDED'}
 if($revokes -lt 1){throw 'REVOCATION_NOT_ATTEMPTED'}
}
foreach($script:case in @('healthy','expired','cancelDown')){
 $script:readyCalls=0;$failure=$null;try{Wait-CollectorApplication {return ($script:case -ne 'cancelDown')}}catch{$failure=$_.Exception.Message}
 $expected=switch($case){healthy{$null} expired{'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'} cancelDown{'COLLECTOR_START_CANCELLED'}}
 if($failure -cne $expected){throw 'STARTUP_WAIT_CASE'}
}
Write-Host 'COLLECTOR_RECOVERY_FIXTURES_PASSED: 12 loop and 3 startup cases.'
