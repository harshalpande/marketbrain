# Offline fixtures only: never starts a service or scheduled task.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
$script:count=0
function Check($ok,$label){if(-not $ok){throw "FAILED: $label"};$script:count++}
$base=[pscustomobject]@{state='Stopped';startType=3;imagePath=($env:WINDIR+'\system32\svchost.exe -k LocalService');account='NT AUTHORITY\LocalService';sddl='D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCLCSWLOCRRC;;;BA)(A;;CCLCSWLOCRRC;;;IU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)';policyPresent=$false;type='NTP';ntpServer='time.example.test,0x9';ntpClientEnabled=1}
function Clone($o){$o|ConvertTo-Json|ConvertFrom-Json}
Assert-PaytmTimeRepairBaseline $base
foreach($field in @('sddl','state','startType','imagePath','account','policyPresent','type','ntpServer','ntpClientEnabled')){
 $v=Clone $base
 switch($field){startType{$v.$field=2};policyPresent{$v.$field=$true};ntpClientEnabled{$v.$field=0};ntpServer{$v.$field=''};default{$v.$field='changed'}}
 $failed=$false;try{Assert-PaytmTimeRepairBaseline $v}catch{$failed=$true};Check $failed "baseline rejects $field"
}
foreach($field in @('sddl','imagePath','account','policyPresent','type','ntpServer','ntpClientEnabled')){
 $v=Clone $base;$v.$field=if($field -eq 'policyPresent'){$true}elseif($field -eq 'ntpClientEnabled'){0}else{'changed'}
 $failed=$false;try{Assert-PaytmTimeRepairPreserved $base $v}catch{$failed=$true};Check $failed "preserve $field"
}
function Get-PaytmTimeRepairSnapshot {$script:reads++;if($script:reads -eq 1){return (Clone $base)};$v=Clone $base;$v.state='Running';$v.startType=2;if($script:drift){$v.ntpServer='changed'};return $v}
function Wait-PaytmTimeRepairRunning {if($script:waitFail){throw 'fixture wait failure'}}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){$script:calls+=,$Arguments;@{tool=$Tool;arguments=$Arguments;exitCode=$(if($Arguments -eq $script:failArg){1}else{0});output='fixture'}}
foreach($scenario in @('pass','config W32Time start= auto','start W32Time','/resync /rediscover','/query /status /verbose','/query /source','wait','drift')){
 $script:reads=0;$script:calls=@();$script:failArg=$scenario;$script:drift=$scenario -eq 'drift';$script:waitFail=$scenario -eq 'wait';$script:saves=0
 $r=@{commands=@();status='REVIEW_REQUIRED'};$err=$null
 try{Invoke-PaytmTimeRepairSequence $r {$script:saves++}}catch{$err=$_.Exception.Message}
 if($scenario -eq 'pass'){Check (-not $err) 'success';Check ($r.status -eq 'TIME_SERVICE_RUNNING_AUTOMATIC_RESYNC_ACCEPTED_ALIGNMENT_PENDING') 'alignment remains pending';Check (($script:calls -join '|') -eq 'config W32Time start= auto|start W32Time|/resync /rediscover|/query /status /verbose|/query /source') 'exact command sequence'}else{Check ([bool]$err) "failure $scenario";Check ($r.status -eq 'REVIEW_REQUIRED') "no false success $scenario"}
 if($scenario -eq '/resync /rediscover'){Check ($script:calls.Count -eq 5) 'capture status even after sync failure'}
 if($scenario -eq 'config W32Time start= auto'){Check ($script:calls.Count -eq 1) 'config failure stops sequence'}
 if($scenario -eq 'start W32Time'){Check ($script:calls.Count -eq 2) 'start failure stops sequence'}
 Check ($script:saves -ge 2) "checkpoint $scenario"
}
foreach($file in @('PaytmTimeServiceRepair.ps1','InvokePaytmTimeRepairWorker.ps1','RepairPaytmWindowsTime.ps1')){
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) "parse $file"
}
Write-Host "PASS: $script:count offline assertions; no service/task changes performed."
