#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
function New-Round {
 [pscustomobject]@{elapsedSeconds=2.0;wallSeconds=2.0;service=@{state='Running';startType=2};sync=@{synchronizedReported=$true};windowsStatus=@{output="Time since Last Good Sync Time: 20.0s`nPoll Interval: 10 (1024s)"};vps=@{ntp='yes';bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};application=@{bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};transport=@{tlsVerified=$true};assessment=$null}
}
$count=0
$r=New-Round
if(-not (Get-PaytmLiveHealthAssessment $r).collectionPassed){throw 'Healthy fixture'};$count++
foreach($change in @(
 {$r.elapsedSeconds=8},{$r.wallSeconds=10},{$r.service.state='Stopped'},{$r.sync.synchronizedReported=$false},
 {$r.windowsStatus.output='unrecognized'},{$r.windowsStatus.output="Time since Last Good Sync Time: 4000s`nPoll Interval: 10 (1024s)"},
 {$r.vps.ntp='no'},{$r.vps.bounds.usable=$false},{$r.application.bounds.lowerOffsetSeconds=-6},
 {$r.application.bounds.lowerOffsetSeconds=[double]::NaN},{$r.transport.tlsVerified=$false},
 {$r.application.bounds.lowerOffsetSeconds=4;$r.application.bounds.upperOffsetSeconds=5;$r.vps.bounds.lowerOffsetSeconds=-5;$r.vps.bounds.upperOffsetSeconds=-4}
)){
 $r=New-Round;& $change
 if((Get-PaytmLiveHealthAssessment $r).collectionPassed){throw 'Unsafe health accepted'};$count++
}
$args=Get-PaytmLiveHealthCurlArguments
if($args[0] -cne '-q' -or $args[$args.IndexOf('--noproxy')+1] -cne '' -or $args[$args.IndexOf('--proxy')+1] -cne 'http://127.0.0.1:18889' -or $args -contains '--insecure' -or $args -contains '--location'){throw 'Proxy contract'};$count++
function Invoke-PaperRuntimeProcess {param($Tool,$Arguments,$Root,$Seconds) @{exitCode=$script:transportExit;stdout=$script:transportOutput;stderr='';elapsedSeconds=0}}
foreach($spec in @(@(0,'503|127.0.0.1',$true),@(60,'000|127.0.0.1',$false),@(0,'200|1.2.3.4',$false),@(0,'garbage',$false))){
 $script:transportExit=$spec[0];$script:transportOutput=$spec[1]
 if((Invoke-PaytmLiveHealthTransport $PSScriptRoot).tlsVerified -ne $spec[2]){throw 'Transport result'};$count++
}
# Execute the actual controller with only operating-system/network boundaries replaced.
$src=Get-Content (Join-Path $PSScriptRoot 'TestPaytmLiveHealthCollector.ps1') -Raw
# Literal replacement avoids interpolation in the import-removal expression.
foreach($name in @('PaytmClockComparison.ps1','PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1')){$src=$src.Replace(". (Join-Path `$PSScriptRoot '$name')",'')}
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('mb-live-health-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $fixtureRoot
$e=Join-Path $fixtureRoot 'receipt.json';'{}'|Set-Content $e
$src=$src.Replace('92434854384A0EF910587571CF2693178B143AD9CD4E4A39F725CC34BF342929',(Get-FileHash $e).Hash)
function Resolve-PaytmClockTool($Name){$Name}
function Invoke-PaperRuntimeProcess {param($Tool,$Arguments,$Root,$Seconds) @{exitCode=0;stdout='Release 0.83';stderr=''}}
function Assert-TunnelDefaults($Settings){}
function Invoke-PaytmClockDocker($Tool,$Arguments,$Root){if($Arguments[1] -eq 'show'){'fixture'}else{'npipe://fixture'}}
function Get-PaytmClockContainer($Tool,$Root){[pscustomobject]@{identity=@{id='fixture';image='fixture';startedAt='fixture'};token='SECRET_DO_NOT_LOG'}}
function Get-PaytmTimeRepairSnapshot { @{state='Running';startType=2} }
function Assert-PaytmTimeRepairPreserved($Before,$After){}
function Start-Sleep {param($Seconds)}
function Read-Host($Prompt){if($Prompt -like '*HEALTH-CHECK*'){'HEALTH-CHECK'}else{'KEY-REVIEWED'}}
function Invoke-PaytmLiveHealthRound($Plink,$Root,$Token){
 if($Token -cne 'SECRET_DO_NOT_LOG'){throw 'Token boundary'}
 if($script:scenario -eq 'failure'){throw 'LIVE_HEALTH_VPS_READ_FAILED'}
 $r=New-Round;if($script:scenario -eq 'findings'){$r.transport.tlsVerified=$false}
 $r.assessment=Get-PaytmLiveHealthAssessment $r;return $r
}
foreach($script:scenario in @('pass','findings','failure')){
 $out=Join-Path $fixtureRoot $script:scenario;$errorText=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$errorText=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$report=$raw|ConvertFrom-Json
 if($raw.Contains('SECRET_DO_NOT_LOG')){throw 'Credential leaked'}
 $expected=switch($script:scenario){'pass'{'LIVE_HEALTH_COLLECTION_PASSED_PUBLISHER_PENDING'} 'findings'{'LIVE_HEALTH_COLLECTION_WITH_FINDINGS'} 'failure'{'REVIEW_REQUIRED'}}
 if($report.status -cne $expected){throw "Controller $script:scenario : $errorText"}
 if($report.settingsChanged -or $report.ordersEnabled -or $report.applicationChanged -or -not $report.keyCleanupOwnerConfirmed){throw 'Controller authority'}
 $count++
}
Write-Host "PASS: $count collector and controller fixtures; no external calls or settings changes."
