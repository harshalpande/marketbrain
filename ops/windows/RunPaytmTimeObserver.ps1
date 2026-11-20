#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18'){throw 'TIME_OBSERVER_SYSTEM_REQUIRED'}
$path=Join-Path $root 'snapshot.json';$sequence=0L
function Read-FixedTimeQuery([ValidateSet('/query /status /verbose','/query /source')][string]$Arguments){
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=Join-Path $env:WINDIR 'System32\w32tm.exe';$p.StartInfo.Arguments=$Arguments
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    try{if(-not $p.Start()){throw 'TIME_OBSERVER_START'};$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(2000)){throw 'TIME_OBSERVER_TIMEOUT'};if(-not $o.Wait(500) -or -not $e.Wait(500)){throw 'TIME_OBSERVER_DRAIN'};if($o.Result.Length -gt 12000){throw 'TIME_OBSERVER_SIZE'};@{exitCode=$p.ExitCode;output=$o.Result}}finally{try{if(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(1000)}}catch{};$p.Dispose()}
}
$boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
while($true){
    $start=[Diagnostics.Stopwatch]::GetTimestamp()
    try{
        $status=Read-FixedTimeQuery '/query /status /verbose';$source=Read-FixedTimeQuery '/query /source'
        $service=Get-Service W32Time;$startType=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time' -Name Start).Start
        $sequence++
        $v=@{version=1;bootId=$boot;sequence=$sequence;startTicks=$start;endTicks=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency;status=$status;source=$source;service=@{state=[string]$service.Status;startType=$startType}}
        $json=$v|ConvertTo-Json -Depth 5 -Compress;if([Text.Encoding]::UTF8.GetByteCount($json) -gt 16384){throw 'TIME_OBSERVER_SIZE'}
        $temp=$path+'.new';[IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
    }catch{if([IO.File]::Exists($path)){[IO.File]::Delete($path)};throw}
    Start-Sleep -Seconds 1
}
