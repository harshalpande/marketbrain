. "$PSScriptRoot/PaytmClockLogin.ps1"
$n='a'*32
$r=[pscustomobject]@{exitCode=0;stdout="MB_CLOCK_V1|$n|1794800000000|yes";stderr=''}
if(-not (Assert-ClockLoginReply $r $n $true).ntpSynchronized){throw 'valid response failed'}
$count=1
foreach($case in @(
 @{exitCode=0;stdout="MB_CLOCK_V1|$('b'*32)|1794800000000|yes";stderr=''},
 @{exitCode=255;stdout=$r.stdout;stderr=''},
 @{exitCode=0;stdout=($r.stdout+"`nextra");stderr=''})){
 $caught=$false;try{Assert-ClockLoginReply ([pscustomobject]$case) $n $true}catch{$caught=$true}
 if(-not $caught){throw 'bad allowed response accepted'};$count++
}
$null=Assert-ClockLoginReply ([pscustomobject]@{exitCode=1;stdout='';stderr='CLOCK_READ_DENIED_OR_UNAVAILABLE'}) $n $false;$count++
$caught=$false;try{Assert-ClockLoginReply ([pscustomobject]@{exitCode=255;stdout='';stderr='Permission denied'}) $n $false}catch{$caught=$true}
if(-not $caught){throw 'authentication failure mistaken for command denial'};$count++
$r=Invoke-ClockLoginNative (Get-Process -Id $PID).Path @('-NoProfile','-Command','[Console]::Out.Write("output");[Console]::Error.Write("diagnostic");exit 3') 10
if($r.exitCode -ne 3 -or $r.stdout -cne 'output' -or $r.stderr -cne 'diagnostic'){throw 'native capture failed'};$count++
$caught=$false;try{Invoke-ClockLoginNative (Get-Process -Id $PID).Path @('-NoProfile','-Command','Start-Sleep 20') 1}catch{$caught=$_.Exception.Message -eq 'CLOCK_LOGIN_TIMEOUT'}
if(-not $caught){throw 'timeout failed'};$count++
Write-Host "$count clock login tests passed"
