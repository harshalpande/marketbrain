#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthActivation.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-publication-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$e=Join-Path $work 'accepted.json';[IO.File]::WriteAllText($e,'{"newImageId":"fixture-image","container":{"image":"fixture-image"}}')
$src=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmUnattendedHealthPreflight.ps1'))
$src=[regex]::Replace($src,'(?m)^\. \(Join-Path \$PSScriptRoot .*\)\r?\n','')
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$src=$src.Replace('61F63499AA91C62C59C3470B56BC90B13B1BDD6145D370060CB1CC199954BECB',(Get-FileHash $e).Hash)
$src=$src.Replace('0F5CA8DE54E0FCFF966286ADD4ED209EFC7E53AD50255699B56540DE663CA609',(Get-FileHash $e).Hash)
function Invoke-PaytmHealthLifecycle($Publish,$Revoke,$Checkpoint){
 $null=& $Publish;$null=& $Publish;$null=& $Revoke
 if($script:case -eq 'lifecyclefail'){throw 'HEALTH_LIFECYCLE_ROUTE_MISMATCH'}
 @{passed=$true}
}
$src=$src.Replace('FBC42DCFB70F063035BD3F18C2F286E0EF92EFFA30E29D85D0E0C0B56DD74005',(Get-FileHash $e).Hash)
function Get-LocalUser { if($script:case -eq 'collision'){@{Name='marketbrain-health'}} }
function Get-ScheduledTask {}
function Get-Service { @{Status='Running'} }
function New-PaytmClockSshArguments($Nonce) { @('read-only',$Nonce) }
function Resolve-PaytmClockTool($Name){$Name}
function Invoke-PaperRuntimeProcess($File,$Arguments,$Root,$Limit) {
 if($File -eq 'plink.exe'){
  if($Arguments[0] -eq '-V'){return @{exitCode=0;stdout='Release 0.83';stderr=''}}
  if($script:case -eq 'vpsfail'){return @{exitCode=1;stdout='';stderr='private'}}
  if($Arguments[-1] -notmatch 'MB_HEALTH_PREFLIGHT_V1\|([a-f0-9]{32})\|'){throw 'Unexpected remote command'}
  return @{exitCode=0;stdout=('MB_HEALTH_PREFLIGHT_V1|'+$Matches[1]+'|1|1|0');stderr=''}
 }
 if($File -ne 'docker.exe'){throw 'Unexpected executable'}
 if($Arguments[0] -eq 'ps'){
  if($script:case -eq 'locatefail'){return @{exitCode=1;stdout='';stderr='private native error';elapsedSeconds=0.1}}
  return @{exitCode=0;stdout=('a'*64);stderr='';elapsedSeconds=0.1}
 }
 if($Arguments[0] -eq 'inspect'){
  $v=@{Id=('a'*64);Image='fixture-image';Config=@{Env=@();Labels=@{'com.docker.compose.project.working_dir'=$Root}};State=@{Running=$true;Paused=$false;Restarting=$false;ExitCode=0;OOMKilled=$false}}
  return @{exitCode=0;stdout=($v|ConvertTo-Json -Depth 8);stderr='';elapsedSeconds=0.1}
 }
 throw 'Unexpected Docker mutation'
}
function Assert-PaperRuntimeContainer {}
function Assert-TunnelDefaults {}
function Invoke-PaytmClockDocker($d,$a,$r){if($a[0] -eq 'context' -and $a[1] -eq 'show'){'default'}else{'npipe://fixture'}}
function Get-PaytmClockContainer { @{identity=@{id='fixture'};token=('R'*64)} }
function ConvertTo-PaperRuntimeEnvironment { @{MARKETBRAIN_PAYTM_HEALTH_TOKEN=('H'*64);MARKETBRAIN_PAYTM_ENABLED='false';MARKETBRAIN_PAYTM_ACCESS_TOKEN=''} }
function Assert-PaytmWriterLocked {}
function Read-PaytmHealthPreflightAccount { $script:accounts++;if($script:case -eq 'accountdrift' -and $script:accounts -gt 1){'changed'}else{'same'} }
function Invoke-PaytmHealthActivationRoute($Command){if($Command -ne 'status'){throw 'Unexpected route command'};@{state='LOCKED'}}
function Read-Host($Prompt){if($Prompt -like '*HEALTH-CHECK*'){'HEALTH-CHECK'}else{'KEY-REVIEWED'}}
function Start-Sleep {}
function Get-PaytmTimeRepairSnapshot { @{state='Running';startType=2} }
function Assert-PaytmTimeRepairPreserved {}
function Invoke-PaytmLiveHealthRound {
 if($script:case -eq 'collectionfail'){throw 'LIVE_HEALTH_VPS_READ_FAILED'}
 $r=[pscustomobject]@{elapsedSeconds=2.0;wallSeconds=2.0;service=@{state='Running';startType=2};sync=@{synchronizedReported=$true};windowsStatus=@{output="Time since Last Good Sync Time: 20s`nPoll Interval: 10 (1024s)"};vps=@{ntp='yes';bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};application=@{bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};transport=@{tlsVerified=$true};assessment=$null}
 if($script:case -eq 'unhealthy'){$r.sync.synchronizedReported=$false}
 $r.assessment=Get-PaytmLiveHealthAssessment $r;return $r
}
function Invoke-PaytmHealthHttp($Command,$Token,$Body){
 if($Token -cne ('H'*64)){throw 'Token mismatch'}
 $boot='11111111-1111-1111-1111-111111111111'
 if($Command -eq 'challenge'){return @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;challenge=$boot;validForSeconds=10;accepted=$false;ordersEnabled=$false;status='CHALLENGE'}}
 $script:submits++
 if($script:case -eq 'revocationfail' -and -not $Body.synchronizedClock){throw 'HEALTH_PUBLISHER_HTTP_FAILED'}
 $yes=[bool]$Body.synchronizedClock -and $script:case -ne 'serverreject'
 @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;accepted=$yes;ordersEnabled=$false;status=$(if($yes){'HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED'}else{'UNHEALTHY_AND_LOCKED'})}
}

$count=0
foreach($script:case in @('pass','collision','vpsfail')){
 $script:accounts=0;$script:submits=0;$out=Join-Path $work $script:case;$err=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$r=$raw|ConvertFrom-Json
 if($script:case -eq 'pass'){
  if($err -or $r.status -cne 'UNATTENDED_HEALTH_PREFLIGHT_PASSED_INSTALLATION_PENDING' -or -not $r.accountPreserved -or -not $r.writerLocked){throw "Pass: $err"}
 }elseif($script:case -eq 'collision'){
  if($r.status -cne 'UNATTENDED_HEALTH_PREFLIGHT_FINDINGS'){throw 'Collision missed'}
 }elseif(-not $err -or $r.failure -cne 'LIVE_HEALTH_PREFLIGHT_VPS_FAILED'){throw 'VPS failure missed'}
 if($r.healthPublicationAttempted -or $raw.Contains('H'*64) -or $raw.Contains('R'*64) -or $r.ordersEnabled){throw 'Mutation or leak'}
 $count++
}
Write-Host "PASS: $count read-only unattended preflight workflows."
