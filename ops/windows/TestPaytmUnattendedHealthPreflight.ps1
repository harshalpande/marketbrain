#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-live-publication-20261115-033221-87b397d980604582bf192a89d35bceab.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmClockComparison.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthDeploymentPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthActivation.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthLifecycle.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$route=@{Root=$root};$application=@{Docker=$null;Id=$null;Token=$null};$healthToken=$null;$account=$null
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$context=$null;$keyConfirmed=$false;$keyRequested=$false
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';startedUtc=[DateTimeOffset]::UtcNow.ToString('o');applicationCommands=[Collections.Generic.List[object]]::new();applicationDiscovery=$null;inventory=$null;healthPublicationAttempted=$false;publications=@();finalRevocationVerified=$false;accountPreserved=$false;writerLocked=$false;rounds=@();assessment=$null;before=$null;after=$null;container=$null;containerUnchanged=$false;failure=$null;elapsedSeconds=0;keyCleanupOwnerConfirmed=$false;settingsChanged=$false;databaseWritesPerformed=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;applicationChanged=$false;gatewayStarted=$false;absoluteUtcAccuracyProven=$false;automaticSynchronizationProven=$false;quoteTimingApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-unattended-preflight-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
function Save-LiveHealth {
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    [IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
}
function Save-Report { Save-LiveHealth } # Shared application helpers checkpoint through this hook.
try{
    Save-LiveHealth
    if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'FBC42DCFB70F063035BD3F18C2F286E0EF92EFFA30E29D85D0E0C0B56DD74005'){throw 'LIVE_HEALTH_EVIDENCE_MISMATCH'}
    $report.sourceHashes=@{}
    foreach($name in @('TestPaytmUnattendedHealthPreflight.ps1','PaytmHealthPublisher.ps1','PaytmHealthActivation.ps1','PaytmHealthLifecycle.ps1','PaytmApplicationRoute.ps1','PaytmHealthDeploymentPreflight.ps1','PaytmLiveHealthCollector.ps1','PaytmTimeServiceRepair.ps1','PaytmClockComparison.ps1','PaperRuntimeReview.ps1','PaperRuntimeDeployment.ps1','PaperAccountReadReview.ps1','PaytmTunnelVerification.ps1')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    Write-Host '[5%] Read-only unattended collector preflight. No publication, account creation, task installation, restart or deployment.'
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
    $application.Docker=$docker;$application.Token=$context.token
    $current=Get-PaytmApplicationContainer;$application.Id=$current.Id
    $accepted=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
    $expectedImage=$accepted.container.image
    if($current.Image -cne $expectedImage){throw 'LIVE_HEALTH_DEPLOYED_IMAGE_CHANGED'}
    $map=ConvertTo-PaperRuntimeEnvironment $current.Config.Env
    $healthToken=$map['MARKETBRAIN_PAYTM_HEALTH_TOKEN']
    if($healthToken -cnotmatch '^[A-Za-z0-9_-]{32,128}$' -or $healthToken -ceq $context.token -or $map.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $map.MARKETBRAIN_PAYTM_ACCESS_TOKEN){throw 'LIVE_HEALTH_TOKEN_OR_PROVIDER_CONFIGURATION'}
    Assert-PaytmWriterLocked;$account=Read-PaytmHealthPreflightAccount $application.Token
    $null=Invoke-PaytmHealthActivationRoute 'status'
    $map=$null;$current=$null
    $keyRequested=$true
    Write-Host 'In Pageant load ONLY your original ADMINISTRATOR PPK for marketbrain-admin, not the restricted gateway key. Enter its passphrase in Pageant only. No private key is copied or passed to Docker.'
    if((Read-Host 'Keep time settings unchanged and jobs/tests idle. Type HEALTH-CHECK once the administrator key is available') -cne 'HEALTH-CHECK'){throw 'CLOCK_OWNER_CONFIRMATION_REQUIRED'}
    $keyConfirmed=$true
    $report.before=Get-PaytmTimeRepairSnapshot;Save-LiveHealth
    Write-Host '[40%] Inspect proposed collector identity and task names; never read private key content.'
    $local=@(Get-LocalUser -ErrorAction Stop | Where-Object Name -CEQ 'marketbrain-health')
    $task=@(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -ceq 'MarketBrain-Paytm-Health' -and $_.TaskPath -ceq '\' })
    $agent=Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
    $nonce=[guid]::NewGuid().ToString('N')
    $command='printf "MB_HEALTH_PREFLIGHT_V1|'+$nonce+'|"; if test -x /usr/bin/python3; then printf "1|"; else printf "0|"; fi; if test -x /usr/bin/timedatectl; then printf "1|"; else printf "0|"; fi; if getent passwd marketbrain-health >/dev/null; then printf "1\n"; else printf "0\n"; fi'
    $arguments=New-PaytmClockSshArguments $nonce
    $arguments[-1]=$command
    Write-Host '[65%] Read-only pinned VPS prerequisite check using the current administrator session.'
    $probe=Invoke-PaperRuntimeProcess $plink $arguments $root 10
    if($probe.exitCode -ne 0 -or $probe.stdout.Trim() -cnotmatch ('^MB_HEALTH_PREFLIGHT_V1\|'+$nonce+'\|([01])\|([01])\|([01])$')){throw 'LIVE_HEALTH_PREFLIGHT_VPS_FAILED'}
    $report.inventory=@{vpsPythonPresent=($Matches[1] -eq '1');vpsTimedatectlPresent=($Matches[2] -eq '1');vpsCollectorAccountExists=($Matches[3] -eq '1');windowsCollectorAccountExists=($local.Count -gt 0);collectorTaskExists=($task.Count -gt 0);sshAgentServicePresent=($null -ne $agent);adminKeyUsedForReadOnlyInventory=$true;adminKeyApprovedForBackgroundUse=$false;installationPerformed=$false}
    Save-LiveHealth
    $report.after=Get-PaytmTimeRepairSnapshot
    Assert-PaytmTimeRepairPreserved $report.before $report.after
    if($report.before.state -cne $report.after.state -or $report.before.startType -ne $report.after.startType){throw 'LIVE_HEALTH_SERVICE_CHANGED'}
    $after=Get-PaytmClockContainer $docker $root
    if(($after.identity|ConvertTo-Json -Compress) -cne ($context.identity|ConvertTo-Json -Compress) -or $after.token -cne $context.token){throw 'CLOCK_APPLICATION_CHANGED_DURING_COLLECTION'}
    $report.containerUnchanged=$true
    Assert-PaytmWriterLocked;$report.writerLocked=$true
    if((Read-PaytmHealthPreflightAccount $application.Token) -cne $account){throw 'LIVE_HEALTH_ACCOUNT_CHANGED'}
    $report.accountPreserved=$true
    $report.status=if($report.inventory.vpsPythonPresent -and $report.inventory.vpsTimedatectlPresent -and -not $report.inventory.vpsCollectorAccountExists -and -not $report.inventory.windowsCollectorAccountExists -and -not $report.inventory.collectorTaskExists){'UNATTENDED_HEALTH_PREFLIGHT_PASSED_INSTALLATION_PENDING'}else{'UNATTENDED_HEALTH_PREFLIGHT_FINDINGS'}

}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(CLOCK|LIVE_HEALTH|TIME_REPAIR|APP_ROUTE|HEALTH_ACTIVATION|HEALTH_PUBLISHER|HEALTH_LIFECYCLE)_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_COLLECTION_FAILED_CHECK_LOCAL_PREREQUISITES'}
}finally{
    $healthToken=$null;$application.Token=$null;$context=$null;$after=$null;$script:publicationRound=$null
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
