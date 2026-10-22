#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmClockComparison.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$context=$null;$keyConfirmed=$false;$keyRequested=$false
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';startedUtc=[DateTimeOffset]::UtcNow.ToString('o');samples=@();assessment=$null;container=$null;containerUnchanged=$false;failure=$null;elapsedSeconds=0;keyCleanupOwnerConfirmed=$false;settingsChanged=$false;databaseWritesPerformed=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;applicationChanged=$false;gatewayStarted=$false;absoluteUtcAccuracyProven=$false;automaticSynchronizationProven=$false;quoteTimingApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-snapshot-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    Write-Host '[5%] Read-only Windows/VPS/main-Java clock snapshot. No deployment, service or clock changes.'
    if(-not [Diagnostics.Stopwatch]::IsHighResolution){throw 'CLOCK_MONOTONIC_TIMER_REQUIRED'}
    $plink=Resolve-PaytmClockTool 'plink.exe'
    $docker=Resolve-PaytmClockTool 'docker.exe'
    $v=Invoke-PaperRuntimeProcess $plink @('-V') $root 5
    if($v.exitCode -ne 0 -or ($v.stdout+$v.stderr) -notmatch 'Release (\d+)\.(\d+)' -or [version]($Matches[1]+'.'+$Matches[2]) -lt [version]'0.83'){throw 'CLOCK_PLINK_VERSION_REVIEW'}
    if([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'marketbrain-vps-admin.pub')).Trim() -cne 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOVSxqHLjDm2skmoTLWNmCnjAA7Vh6SNf8lHqc0GSOu marketbrain-vps-admin'){throw 'CLOCK_ADMIN_PUBLIC_KEY_CHANGED'}
    $settingsPath='HKCU:\Software\SimonTatham\PuTTY\Sessions\Default%20Settings'
    $settings=if(Test-Path -LiteralPath $settingsPath){Get-ItemProperty -LiteralPath $settingsPath}else{$null}
    Assert-TunnelDefaults $settings
    if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'CLOCK_DOCKER_OVERRIDE_REVIEW'}
    $dockerContext=Invoke-PaytmClockDocker $docker @('context','show') $root
    $endpoint=Invoke-PaytmClockDocker $docker @('context','inspect',$dockerContext,'--format','{{.Endpoints.docker.Host}}') $root
    if($endpoint -notmatch '^npipe://'){throw 'CLOCK_LOCAL_DOCKER_REQUIRED'}
    $context=Get-PaytmClockContainer $docker $root;$report.container=$context.identity
    $keyRequested=$true
    Write-Host 'In Pageant load ONLY your original ADMINISTRATOR PPK for marketbrain-admin, not the restricted gateway key. Enter its passphrase in Pageant only. No private key is copied or passed to Docker.'
    if((Read-Host 'Keep time settings unchanged and jobs/tests idle. Type CLOCK-CHECK once the administrator key is available') -cne 'CLOCK-CHECK'){throw 'CLOCK_OWNER_CONFIRMATION_REQUIRED'}
    $keyConfirmed=$true
    $collectionStart=[DateTimeOffset]::UtcNow;$collection=[Diagnostics.Stopwatch]::StartNew()
    for($i=1;$i -le 5;$i++){
        $percent=10+($i-1)*15
        Write-Progress -Activity 'Clock snapshot' -Status "Pair $i/5" -PercentComplete $percent
        Write-Host "[$percent%] Pair $i/5: pinned SSH VPS time, then actual Java account-read timestamp."
        $nonce=[guid]::NewGuid().ToString('N')
        $start=[DateTimeOffset]::UtcNow;$sw=[Diagnostics.Stopwatch]::StartNew()
        $ssh=Invoke-PaperRuntimeProcess $plink (New-PaytmClockSshArguments $nonce) $root 15
        $end=[DateTimeOffset]::UtcNow;$sw.Stop()
        if($ssh.exitCode -ne 0){throw 'CLOCK_SSH_FAILED_CHECK_ADMIN_PAGEANT_KEY_OR_HOST_PIN'}
        $receipt=Read-PaytmClockSshReceipt $ssh.stdout $nonce
        $report.samples+= [pscustomobject]@{source='VPS';pair=$i;ntpSynchronized=$receipt.ntp;bounds=(Get-PaytmClockBounds $start $end $sw.Elapsed.TotalSeconds $receipt.time)}
        $start=[DateTimeOffset]::UtcNow;$sw=[Diagnostics.Stopwatch]::StartNew()
        $appTime=Invoke-PaytmClockApplication $context.token
        $end=[DateTimeOffset]::UtcNow;$sw.Stop()
        $report.samples+= [pscustomobject]@{source='APPLICATION';pair=$i;bounds=(Get-PaytmClockBounds $start $end $sw.Elapsed.TotalSeconds $appTime)}
    }
    $collectionEnd=[DateTimeOffset]::UtcNow;$collection.Stop()
    $report.assessment=Get-PaytmClockAssessment $report.samples ($collectionEnd-$collectionStart).TotalSeconds $collection.Elapsed.TotalSeconds
    $after=Get-PaytmClockContainer $docker $root
    if(($after.identity|ConvertTo-Json -Compress) -cne ($context.identity|ConvertTo-Json -Compress) -or $after.token -cne $context.token){throw 'CLOCK_APPLICATION_CHANGED_DURING_COLLECTION'}
    $report.containerUnchanged=$true
    $report.status=if($report.assessment.screenPassed){'CLOCK_SNAPSHOT_WITHIN_SCREEN_RELEASE_PENDING'}else{'CLOCK_SNAPSHOT_CAPTURED_WITH_FINDINGS'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^CLOCK_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_COLLECTION_FAILED_CHECK_LOCAL_PREREQUISITES'}
}finally{
    $context=$null;$after=$null
    if($keyRequested){
        Write-Host 'Pageant: remove only the administrator key if you added it just for this check. Do not remove keys needed by other active sessions. Keep the encrypted PPK.'
        try{$report.keyCleanupOwnerConfirmed=((Read-Host 'Type KEY-REVIEWED after reviewing Pageant key cleanup') -ceq 'KEY-REVIEWED')}catch{}
    }
    if($keyRequested -and -not $report.keyCleanupOwnerConfirmed){$report.status='REVIEW_REQUIRED';if(-not $report.failure){$report.failure='CLOCK_KEY_CLEANUP_NOT_CONFIRMED'}}
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Clock snapshot' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'Five-second screening is NOT a trading threshold or proof of absolute accuracy, NTP repair, drift stability, or approval safety.'
}
if($report.failure){throw $report.failure}
