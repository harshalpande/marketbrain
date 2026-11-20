# PS5-compatible read-only time observation contract. No actions on import.
function Get-TimeObservationBootId {
    # Stable across users/processes; changes after a Windows restart.
    (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Assert-TimeObservationAcl([string]$Path) {
    if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TIME_OBSERVER_REPARSE'}
    $acl=Get-Acl -LiteralPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544')
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted){throw 'TIME_OBSERVER_OWNER'}
    $write=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($ace.AccessControlType -eq 'Allow' -and ($ace.FileSystemRights -band $write) -and $ace.IdentityReference.Value -notin $trusted){throw 'TIME_OBSERVER_WRITABLE'}
    }
}
function ConvertFrom-TimeObservation($Value,[string]$BootId,[long]$NowTicks,[long]$Frequency) {
    if($Value.version -ne 1 -or $Value.bootId -cne $BootId -or $Value.frequency -ne $Frequency -or $Value.sequence -lt 1){throw 'TIME_OBSERVER_IDENTITY'}
    if($Value.startTicks -isnot [long] -or $Value.endTicks -isnot [long] -or $Value.startTicks -gt $Value.endTicks -or $Value.endTicks -gt $NowTicks){throw 'TIME_OBSERVER_TIMING'}
    $age=($NowTicks-$Value.startTicks)/[double]$Frequency
    if($age -lt 0 -or $age -gt 8){throw 'TIME_OBSERVER_STALE'}
    if($Value.status.exitCode -ne 0 -or $Value.source.exitCode -ne 0 -or $Value.service.state -cne 'Running' -or $Value.service.startType -ne 2){throw 'TIME_OBSERVER_UNHEALTHY'}
    if($Value.status.output -isnot [string] -or $Value.source.output -isnot [string] -or $Value.status.output.Length -gt 12000 -or $Value.source.output.Length -gt 1024){throw 'TIME_OBSERVER_FORMAT'}
    # Add snapshot age to the reported sync age; never make old evidence younger.
    $pattern='(?im)^(Time since Last Good Sync Time:\s*)([0-9]+(?:\.[0-9]+)?)(s\s*)$'
    $m=[regex]::Match($Value.status.output,$pattern)
    if(-not $m.Success){throw 'TIME_OBSERVER_SYNC_AGE'}
    $seconds=[double]::Parse($m.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)+$age
    $output=$Value.status.output.Remove($m.Groups[2].Index,$m.Groups[2].Length).Insert($m.Groups[2].Index,$seconds.ToString('F6',[Globalization.CultureInfo]::InvariantCulture))
    [pscustomobject]@{status=@{exitCode=0;output=$output};source=$Value.source;service=$Value.service;ageSeconds=$age;sequence=$Value.sequence}
}
function ConvertFrom-TimeObservationJson([string]$Json) {
    # PS7 otherwise coerces ISO boot IDs into DateTime, unlike the PS5 producer.
    if($PSVersionTable.PSVersion -ge [version]'7.5'){ConvertFrom-Json -InputObject $Json -DateKind String}else{ConvertFrom-Json -InputObject $Json}
}
function Read-TimeObservationOnce {
    $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$path=Join-Path $root 'snapshot.json'
    foreach($p in @('C:\ProgramData\MarketBrainPaytmHealth',$root,$path)){Assert-TimeObservationAcl $p}
    $stream=[IO.File]::Open($path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{if($stream.Length -gt 16384){throw 'TIME_OBSERVER_SIZE'};$reader=[IO.StreamReader]::new($stream);try{$buffer=[char[]]::new(16385);$n=$reader.ReadBlock($buffer,0,16385);if($n -gt 16384){throw 'TIME_OBSERVER_SIZE'};$json=[string]::new($buffer,0,$n);$v=ConvertFrom-TimeObservationJson $json}finally{$reader.Dispose()}}finally{$stream.Dispose()}
    ConvertFrom-TimeObservation $v (Get-TimeObservationBootId) ([Diagnostics.Stopwatch]::GetTimestamp()) ([Diagnostics.Stopwatch]::Frequency)
}

function Read-TimeObservation {
    # Snapshot replacement can briefly invalidate a path lookup. Retry only I/O
    # lookup failures, never ACL policy, identity, age or malformed-data failures.
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{return Read-TimeObservationOnce}catch{
            $cause=$_.Exception.GetBaseException()
            $transient=$cause -is [IO.IOException] -or $cause -is [Management.Automation.ItemNotFoundException]
            if(-not $transient -or $attempt -eq 2){throw}
            Start-Sleep -Milliseconds 25
        }
    }
}
