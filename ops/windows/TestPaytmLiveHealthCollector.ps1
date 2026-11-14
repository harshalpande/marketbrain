#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-timed-route-2c397f318f4744808491f291c471c59c.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmClockComparison.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$context=$null;$keyConfirmed=$false;$keyRequested=$false
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';startedUtc=[DateTimeOffset]::UtcNow.ToString('o');rounds=@();assessment=$null;before=$null;after=$null;container=$null;containerUnchanged=$false;failure=$null;elapsedSeconds=0;keyCleanupOwnerConfirmed=$false;settingsChanged=$false;databaseWritesPerformed=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;applicationChanged=$false;gatewayStarted=$false;absoluteUtcAccuracyProven=$false;automaticSynchronizationProven=$false;quoteTimingApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-live-health-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
function Save-LiveHealth {
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    [IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
}
try{
    Save-LiveHealth
    if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '92434854384A0EF910587571CF2693178B143AD9CD4E4A39F725CC34BF342929'){throw 'LIVE_HEALTH_EVIDENCE_MISMATCH'}
    $report.sourceHashes=@{}
    foreach($name in @('TestPaytmLiveHealthCollector.ps1','PaytmLiveHealthCollector.ps1','PaytmTimeServiceRepair.ps1','PaytmClockComparison.ps1','PaperRuntimeReview.ps1','PaperRuntimeDeployment.ps1','PaperAccountReadReview.ps1','PaytmTunnelVerification.ps1')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    Write-Host '[5%] Read-only live health collector rehearsal; no health submission or arming. No deployment, service or clock changes.'
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
    if((Read-Host 'Keep time settings unchanged and jobs/tests idle. Type HEALTH-CHECK once the administrator key is available') -cne 'HEALTH-CHECK'){throw 'CLOCK_OWNER_CONFIRMATION_REQUIRED'}
    $keyConfirmed=$true
    $report.before=Get-PaytmTimeRepairSnapshot;Save-LiveHealth
    for($i=1;$i -le 3;$i++){
        $percent=10+($i-1)*25
        Write-Progress -Activity 'Live health collection' -Status "Fresh round $i/3" -PercentComplete $percent
        Write-Host "[$percent%] Round $i/3: Windows sync, pinned VPS clock, Java clock and fixed-proxy TLS."
        $row=Invoke-PaytmLiveHealthRound $plink $root $context.token
        Assert-PaytmTimeRepairPreserved $report.before $row.service
        $report.rounds+=,$row;Save-LiveHealth
        if($i -lt 3){Start-Sleep -Seconds 2}
    }
    $report.after=Get-PaytmTimeRepairSnapshot
    Assert-PaytmTimeRepairPreserved $report.before $report.after
    if($report.before.state -cne $report.after.state -or $report.before.startType -ne $report.after.startType){throw 'LIVE_HEALTH_SERVICE_CHANGED'}
    $report.assessment=[ordered]@{roundsPassed=@($report.rounds|Where-Object {$_.assessment.collectionPassed}).Count;roundsRequired=3;healthSubmitted=$false;unattendedCollectorInstalled=$false;applicationTransportVerified=$false}
    $after=Get-PaytmClockContainer $docker $root
    if(($after.identity|ConvertTo-Json -Compress) -cne ($context.identity|ConvertTo-Json -Compress) -or $after.token -cne $context.token){throw 'CLOCK_APPLICATION_CHANGED_DURING_COLLECTION'}
    $report.containerUnchanged=$true
    $report.status=if($report.assessment.roundsPassed -eq 3){'LIVE_HEALTH_COLLECTION_PASSED_PUBLISHER_PENDING'}else{'LIVE_HEALTH_COLLECTION_WITH_FINDINGS'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(CLOCK|LIVE_HEALTH|TIME_REPAIR)_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_COLLECTION_FAILED_CHECK_LOCAL_PREREQUISITES'}
}finally{
    $context=$null;$after=$null
    if($keyRequested){
        Write-Host 'Pageant: remove only the administrator key if you added it just for this check. Do not remove keys needed by other active sessions. Keep the encrypted PPK.'
        try{$report.keyCleanupOwnerConfirmed=((Read-Host 'Type KEY-REVIEWED after reviewing Pageant key cleanup') -ceq 'KEY-REVIEWED')}catch{}
    }
    if($keyRequested -and -not $report.keyCleanupOwnerConfirmed){$report.status='REVIEW_REQUIRED';if(-not $report.failure){$report.failure='CLOCK_KEY_CLEANUP_NOT_CONFIRMED'}}
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    Save-LiveHealth
    Write-Progress -Activity 'Live health collection' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No report may be replayed as live health. Five-second screening is NOT a trading threshold or proof of absolute accuracy, NTP repair, drift stability, or approval safety.'
}
if($report.failure){throw $report.failure}
