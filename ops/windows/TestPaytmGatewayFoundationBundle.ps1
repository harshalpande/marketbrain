#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewaySupervisor.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmOperationsReview.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew();$handle=$null
$report=[ordered]@{schemaVersion=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';
    tests=$null;windowsSsh=$null;effectiveConfig=$null;nativeNegativeChecks=@();sourceHashes=[ordered]@{};
    stage='INITIALIZE';nativeInspection=@();failure=$null;failureDetails=$null;elapsedSeconds=0;
    productionAdaptersImplemented=$false;credentialCustodyTested=$false;taskInstalled=$false;
    serviceConfigurationChanged=$false;vpsContacted=$false;gatewayActivated=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-gateway-foundation-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
try{
    foreach($file in @('PaytmGatewaySupervisor.ps1','TestPaytmGatewaySupervisor.ps1','TestPaytmGatewayFoundationBundle.ps1','PaytmTunnelVerification.ps1','PaytmOperationsReview.ps1')){
        $report.sourceHashes[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash
    }
    Write-Progress -Activity 'Paytm gateway foundation' -Status 'Local engineering tests' -PercentComplete 10
    Write-Host '[10%] Offline recovery/security tests plus hidden disposable process fixtures. No PuTTY, Pageant or administrator rights needed.'
    $report.stage='ENGINEERING_TESTS'
    $report.tests=& (Join-Path $PSScriptRoot 'TestPaytmGatewaySupervisor.ps1') -AsObject
    Write-Progress -Activity 'Paytm gateway foundation' -Status 'Installed Windows SSH configuration inspection' -PercentComplete 70
    Write-Host '[70%] Inspect Windows SSH with -G only: no connection, key loading, agent startup, task or account changes.'
    $report.windowsSsh=Get-PaytmWindowsSshInventory
    $report.stage='CLIENT_CONFIGURATION'
    if(-not $report.windowsSsh.windowsOpenSshPresent){throw 'GATEWAY_WINDOWS_CLIENT_MISSING'}
    $known='C:/ProgramData/MarketBrain/Gateway/known_hosts';$pub='C:/ProgramData/MarketBrain/Gateway/gateway.pub'
    $arguments=Get-PaytmGatewaySshArguments $known $pub -InspectOnly
    $handle=Start-TunnelProcess (Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe') $arguments
    $native=Complete-TunnelProcess $handle -LimitSeconds 10
    $report.nativeInspection+=@([pscustomobject]@{name='fixedPaths';exitCode=$native.ExitCode;timedOut=$native.StoppedByRunner;elapsedSeconds=$native.ElapsedSeconds})
    if($native.StoppedByRunner -or $native.ExitCode -ne 0){throw 'GATEWAY_CONFIG_INSPECTION_FAILED'}
    $report.effectiveConfig=Assert-PaytmGatewayEffectiveConfig $native.Stdout $known $pub
    # Negative cases derive from the actual installed client's output, not a guessed fixture.
    $mutations=[ordered]@{
        host=$native.Stdout.Replace('hostname 130.250.191.137','hostname 127.0.0.1')
        user=$native.Stdout.Replace('user marketbrain-gateway','user root')
        password=$native.Stdout.Replace('passwordauthentication no','passwordauthentication yes')
        agentForward=$native.Stdout.Replace('forwardagent no','forwardagent yes')
        hostVerification=[regex]::Replace($native.Stdout,'(?m)^stricthostkeychecking .+$','stricthostkeychecking false')
        wildcard=$native.Stdout.Replace('[127.0.0.1]:18889','[0.0.0.0]:18889')
        remotePort=$native.Stdout.Replace('[127.0.0.1]:18888','[127.0.0.1]:22')
        duplicateIdentity=($native.Stdout+"`nidentityfile ~/.ssh/id_rsa`n")
        remoteForward=($native.Stdout+"`nremoteforward 9000 localhost:22`n")
        proxyCommand=($native.Stdout+"`nproxycommand forbidden`n")
        parseNoise=($native.Stdout+"`nnot-config`n")
        missingUser=[regex]::Replace($native.Stdout,'(?m)^user .+\r?\n','')
    }
    $report.stage='NEGATIVE_CONFIGURATION'
    foreach($case in $mutations.Keys){
        if($mutations[$case] -ceq $native.Stdout){throw 'GATEWAY_NEGATIVE_FIXTURE_NOT_CHANGED'}
        $rejected=$false;try{$null=Assert-PaytmGatewayEffectiveConfig $mutations[$case] $known $pub}catch{$rejected=$true}
        $report.nativeNegativeChecks+=@([pscustomobject]@{name=$case;rejected=$rejected})
        if(-not $rejected){throw 'GATEWAY_NEGATIVE_CONFIG_ACCEPTED'}
    }
    # Windows profile/installation paths often contain spaces; exercise the real native argument parser.
    $spacedKnown='C:/MarketBrain Test/known_hosts';$spacedPublic='C:/MarketBrain Test/gateway.pub'
    $report.stage='SPACED_PATH_CONFIGURATION'
    $handle=Start-TunnelProcess (Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe') (Get-PaytmGatewaySshArguments $spacedKnown $spacedPublic -InspectOnly)
    $spaced=Complete-TunnelProcess $handle -LimitSeconds 10
    $report.nativeInspection+=@([pscustomobject]@{name='spacedPaths';exitCode=$spaced.ExitCode;timedOut=$spaced.StoppedByRunner;elapsedSeconds=$spaced.ElapsedSeconds})
    if($spaced.StoppedByRunner -or $spaced.ExitCode -ne 0){throw 'GATEWAY_SPACED_PATH_INSPECTION_FAILED'}
    $null=Assert-PaytmGatewayEffectiveConfig $spaced.Stdout $spacedKnown $spacedPublic
    $report.effectiveConfig|Add-Member -NotePropertyName spacedPathsVerified -NotePropertyValue $true
    $report.stage='COMPLETE'
    $report.status='GATEWAY_FOUNDATION_PASSED_PROVISIONING_PENDING'
}catch{
    # Do not store arbitrary native output, account details, environment or exception strings.
    $message=$_.Exception.Message
    $report.failure=if($message -cmatch '^GATEWAY_[A-Z_]+$'){$message}elseif($message.StartsWith('SUPERVISOR_TEST_FAILED: ')){$message}else{'GATEWAY_FOUNDATION_CAPTURE_FAILED'}
    $report.failureDetails=[pscustomobject]@{stage=$report.stage;exceptionType=$_.Exception.GetType().Name;hresult=$_.Exception.HResult;scriptLine=$_.InvocationInfo.ScriptLineNumber}
}finally{
    if($null -ne $handle -and $null -eq $handle.Result){$null=Complete-TunnelProcess $handle -StopNow}
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm gateway foundation' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'Success verifies engineering and client configuration only. Dedicated-account key custody, installation, logoff/reboot and real recovery remain pending.'
}
if($report.status -cne 'GATEWAY_FOUNDATION_PASSED_PROVISIONING_PENDING'){throw $report.failure}
