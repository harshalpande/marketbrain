# Definitions only. Snapshot comparison, never a time-setting or synchronization service.
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
function Resolve-PaytmClockTool([ValidateSet('plink.exe','docker.exe')][string]$Name) {
    $found=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if($found){return $found.Source}
    $candidates=@()
    if($Name -eq 'plink.exe'){foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)})){if($base){$candidates+=Join-Path $base 'PuTTY\plink.exe'}}}
    else{if($env:ProgramFiles){$candidates+=Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'};if($env:LOCALAPPDATA){$candidates+=Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'}}
    foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}}
    throw 'CLOCK_REQUIRED_TOOL_NOT_FOUND'
}
function Get-PaytmClockBounds([DateTimeOffset]$Started,[DateTimeOffset]$Ended,[double]$Elapsed,[DateTimeOffset]$Remote) {
    $wall=($Ended-$Started).TotalSeconds
    if(-not [double]::IsFinite($Elapsed) -or $Elapsed -lt 0 -or $wall -lt 0){throw 'CLOCK_SAMPLE_INVALID'}
    $movement=[math]::Abs($wall-$Elapsed)
    $padding=0.002+$movement # Millisecond timestamp quantization plus observed wall/monotonic discrepancy.
    [pscustomobject]@{
        windowsStartedUtc=$Started.ToString('o');windowsEndedUtc=$Ended.ToString('o');sourceUtc=$Remote.ToString('o')
        elapsedSeconds=$Elapsed;wallMovementSeconds=$movement
        lowerOffsetSeconds=($Remote-$Ended).TotalSeconds-$padding
        upperOffsetSeconds=($Remote-$Started).TotalSeconds+$padding
        usable=($Elapsed -le 2 -and $movement -le 0.1)
    }
}
function Get-PaytmClockAssessment($Samples,[double]$WallSeconds,[double]$MonotonicSeconds) {
    $findings=[Collections.Generic.List[string]]::new()
    if(@($Samples).Count -ne 10){$findings.Add('INCOMPLETE_SAMPLES')}
    if(-not [double]::IsFinite($WallSeconds) -or -not [double]::IsFinite($MonotonicSeconds) -or $WallSeconds -lt 0 -or $MonotonicSeconds -lt 0 -or $MonotonicSeconds -gt 120 -or [math]::Abs($WallSeconds-$MonotonicSeconds) -gt 0.1){$findings.Add('CLOCK_MOVEMENT_OR_COLLECTION_WINDOW')}
    $ranges=@{}
    foreach($source in @('VPS','APPLICATION')){
        $rows=@($Samples|Where-Object source -CEQ $source)
        if($rows.Count -ne 5){$findings.Add($source+'_COUNT');continue}
        if(@($rows|Where-Object {-not $_.bounds.usable}).Count){$findings.Add($source+'_EXCESS_DELAY_OR_CLOCK_MOVEMENT')}
        $lo=($rows.bounds.lowerOffsetSeconds|Measure-Object -Minimum).Minimum
        $hi=($rows.bounds.upperOffsetSeconds|Measure-Object -Maximum).Maximum
        $ranges[$source]=[pscustomobject]@{lowerSeconds=$lo;upperSeconds=$hi}
        if($lo -lt -5 -or $hi -gt 5){$findings.Add($source+'_OUTSIDE_FIVE_SECOND_SCREEN')}
        $intersectionLo=($rows.bounds.lowerOffsetSeconds|Measure-Object -Maximum).Maximum
        $intersectionHi=($rows.bounds.upperOffsetSeconds|Measure-Object -Minimum).Minimum
        if($intersectionLo -gt $intersectionHi){$findings.Add($source+'_OFFSET_NOT_STABLE_ACROSS_SAMPLES')}
        if(@($rows.bounds.sourceUtc|Select-Object -Unique).Count -ne 5){$findings.Add($source+'_REPEATED_TIMESTAMP')}
    }
    if(@($Samples|Where-Object {$_.source -ceq 'VPS' -and $_.ntpSynchronized -cne 'yes'}).Count){$findings.Add('VPS_NTP_NOT_CONFIRMED')}
    $relative=$null
    if($ranges.ContainsKey('VPS') -and $ranges.ContainsKey('APPLICATION')){
        $relative=[pscustomobject]@{lowerSeconds=$ranges.APPLICATION.lowerSeconds-$ranges.VPS.upperSeconds;upperSeconds=$ranges.APPLICATION.upperSeconds-$ranges.VPS.lowerSeconds}
        if($relative.lowerSeconds -lt -5 -or $relative.upperSeconds -gt 5){$findings.Add('APPLICATION_VPS_OUTSIDE_FIVE_SECOND_SCREEN')}
    }
    [pscustomobject]@{findings=@($findings.ToArray());offsetsRelativeToWindows=$ranges;applicationMinusVps=$relative;screenPassed=($findings.Count -eq 0);absoluteUtcAccuracyProven=$false;automaticSynchronizationProven=$false;quoteTimingApproved=$false}
}
function New-PaytmClockSshArguments([string]$Nonce) {
    if($Nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'CLOCK_NONCE_INVALID'}
    # No sudo, proxy, forwarding, password, time setting or persistent remote file.
    $command='export LC_ALL=C; test "$(id -un)" = marketbrain-admin || exit 20; n=$(/usr/bin/timeout 5s /usr/bin/timedatectl show -p NTPSynchronized --value) || exit 21; t=$(/usr/bin/date -u +%s%3N) || exit 22; printf "MB_CLOCK_V1|'+$Nonce+'|%s|%s\n" "$t" "$n"'
    @('-ssh','-2','-4','-P','22','-l','marketbrain-admin','-batch','-noshare','-agent','-a','-x','-T','-no-trivial-auth',
        '-hostkey','SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI','-i',(Join-Path $PSScriptRoot 'marketbrain-vps-admin.pub'),'130.250.191.137',$command)
}
function Read-PaytmClockSshReceipt([string]$Text,[string]$Nonce) {
    if($Nonce -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 300 -or $Text.Trim() -cnotmatch ('^MB_CLOCK_V1\|'+$Nonce+'\|([0-9]{13})\|(yes|no)$')){throw 'CLOCK_VPS_RECEIPT_INVALID'}
    [pscustomobject]@{time=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$Matches[1]);ntp=$Matches[2]}
}
function Invoke-PaytmClockDocker([string]$Docker,[string[]]$Arguments,[string]$Root) {
    try{$r=Invoke-PaperRuntimeProcess $Docker $Arguments $Root 15}catch{throw 'CLOCK_DOCKER_UNAVAILABLE'}
    if($r.exitCode -ne 0){throw 'CLOCK_DOCKER_QUERY_FAILED'}
    # Private output may include credentials. Never return it to report/log functions.
    return $r.stdout.Trim()
}
function Get-PaytmClockContainer([string]$Docker,[string]$Root) {
    $id=Invoke-PaytmClockDocker $Docker @('ps','--no-trunc','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') $Root
    if($id -cnotmatch '^[a-f0-9]{64}$'){throw 'CLOCK_CONTAINER_AMBIGUOUS'}
    try{$rows=@((Invoke-PaytmClockDocker $Docker @('inspect',$id) $Root)|ConvertFrom-Json)}catch{throw 'CLOCK_CONTAINER_INSPECTION_FAILED'}
    if($rows.Count -ne 1){throw 'CLOCK_CONTAINER_COUNT'}
    Assert-PaperRuntimeContainer $rows[0] $Root -Memory
    $envMap=ConvertTo-PaperRuntimeEnvironment $rows[0].Config.Env
    if($envMap.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $envMap.MARKETBRAIN_PAYTM_ACCESS_TOKEN){throw 'CLOCK_PAYTM_MUST_REMAIN_DISABLED'}
    [pscustomobject]@{identity=[pscustomobject]@{id=$id;image=$rows[0].Image;startedAt=$rows[0].State.StartedAt};token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN}
}
function Invoke-PaytmClockApplication([string]$Token) {
    try{
        $response=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/v1/paper/account/overview' -Method Get -Headers @{'X-MarketBrain-Paper-Read-Token'=$Token;'Cache-Control'='no-cache'} -NoProxy -TimeoutSec 15 -MaximumRedirection 0 -SkipHttpErrorCheck
        if($response.StatusCode -ne 200 -or ($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'contract'}
        $v=$response.Content|ConvertFrom-Json
        Assert-PaperAccountOverview $v
        if($v.observedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$'){throw 'timestamp'}
        # .NET accepts at most 7 fractional digits; Java Instant can emit 9. Truncate below 100 ns.
        $timestamp=[regex]::Replace($v.observedAtUtc,'(\.\d{7})\d+Z$','$1Z')
        return [DateTimeOffset]::Parse($timestamp,[Globalization.CultureInfo]::InvariantCulture)
    }catch{throw 'CLOCK_APPLICATION_READ_FAILED'} # Never retain HTTP headers/body/token in evidence.
}
