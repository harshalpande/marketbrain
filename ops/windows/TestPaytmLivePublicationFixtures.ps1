#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthActivation.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-publication-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$e=Join-Path $work 'accepted.json';[IO.File]::WriteAllText($e,'{"newImageId":"fixture-image"}')
$src=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmLiveHealthPublication.ps1'))
$src=[regex]::Replace($src,'(?m)^\. \(Join-Path \$PSScriptRoot .*\)\r?\n','')
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$src=$src.Replace('61F63499AA91C62C59C3470B56BC90B13B1BDD6145D370060CB1CC199954BECB',(Get-FileHash $e).Hash)
function Resolve-PaytmClockTool($Name){$Name}
function Invoke-PaperRuntimeProcess($File,$Arguments,$Root,$Limit) {
 if($File -eq 'plink.exe'){return @{exitCode=0;stdout='Release 0.83';stderr=''}}
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
function Invoke-PaytmHealthActivationRoute($Command){if($Command -ne 'lock'){throw 'Unexpected route command'};@{state='LOCKED'}}
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
foreach($script:case in @('pass','unhealthy','collectionfail','serverreject','accountdrift','revocationfail','locatefail')){
 $script:accounts=0;$script:submits=0;$out=Join-Path $work $script:case;$err=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$r=$raw|ConvertFrom-Json
 if($script:case -eq 'pass'){
  if($r.applicationDiscovery.result -cne 'VERIFIED' -or $r.applicationCommands.Count -ne 2){throw 'Real discovery helper did not checkpoint'}
  if($err -or $r.status -cne 'LIVE_HEALTH_PUBLICATION_PASSED_UNATTENDED_PENDING' -or $r.publications.Count -ne 3 -or -not $r.accountPreserved -or -not $r.writerLocked -or $script:submits -ne 4){throw "Pass failed: $err"}
 }elseif(-not $err -or $r.status -cne 'REVIEW_REQUIRED'){throw "Failure accepted: $script:case"}
 if($script:case -eq 'locatefail'){
  if($r.failure -cne 'APP_ROUTE_NATIVE_FAILED_LOCATE' -or $r.healthPublicationAttempted -or $r.applicationCommands.Count -ne 1){throw 'Native failure classification'}
 }elseif($script:case -eq 'revocationfail'){if($r.finalRevocationVerified){throw 'Revocation incorrectly accepted'}}elseif(-not $r.finalRevocationVerified){throw "Missing final revocation: $script:case"}
 if($raw.Contains('H'*64) -or $raw.Contains('R'*64) -or $r.ordersEnabled){throw 'Secret or authority leak'}
 $count++
}
Write-Host "PASS: $count live publication controller fixtures; mocked OS/Docker/SSH/HTTP; no external operations."
