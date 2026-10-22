# Definitions only. Windows resync runs only after the owner confirms in the runner.
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
function Test-PaytmOperationsAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
}
function Invoke-PaytmTimeCommand([string]$Label,[string]$Executable,[string[]]$Arguments) {
    try{
        $r=Invoke-PaperRuntimeProcess $Executable $Arguments $env:WINDIR 30
        $output=([string]$r.stdout+[string]$r.stderr)
        if($output.Length -gt 12000){$output=$output.Substring(0,12000)}
        [pscustomobject]@{label=$Label;exitCode=$r.exitCode;elapsedSeconds=$r.elapsedSeconds;output=$output;failure=$null}
    }catch{
        $code=if($_.Exception.Message -ceq 'RUNTIME_PROCESS_TIMEOUT'){'TIME_COMMAND_TIMEOUT'}else{'TIME_COMMAND_FAILED'}
        [pscustomobject]@{label=$Label;exitCode=$null;elapsedSeconds=$null;output=$null;failure=$code}
    }
}
function Invoke-PaytmWindowsTimeReview {
    $result=[ordered]@{status='REVIEW_REQUIRED';beforeUtc=[DateTimeOffset]::UtcNow.ToString('o');afterUtc=$null;originalServiceState=$null;originalStartType=$null;serviceStartAttempted=$false;resyncAttempted=$false;resyncCommandSucceeded=$false;peerConfigurationChanged=$false;vpsTimeChanged=$false;clockAccuracyProven=$false;commands=@();failure=$null}
    try{
        if(-not (Test-PaytmOperationsAdministrator)){throw 'OPS_ADMIN_POWERSHELL_REQUIRED'}
        $service=Get-Service -Name W32Time -ErrorAction Stop
        $result.originalServiceState=[string]$service.Status;$result.originalStartType=[string]$service.StartType
        if([string]$service.StartType -eq 'Disabled'){throw 'OPS_WINDOWS_TIME_DISABLED_REVIEW_POLICY'}
        $w32tm=Join-Path $env:WINDIR 'System32\w32tm.exe'
        $result.commands+=Invoke-PaytmTimeCommand 'Before status' $w32tm @('/query','/status','/verbose')
        if([string]$service.Status -eq 'Stopped'){
            $result.serviceStartAttempted=$true
            $start=Invoke-PaytmTimeCommand 'Start existing Windows Time service' (Join-Path $env:WINDIR 'System32\sc.exe') @('start','W32Time')
            $result.commands+=$start
            if($start.failure -or $start.exitCode -ne 0){throw 'OPS_WINDOWS_TIME_START_FAILED'}
            $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(20))
        }elseif([string]$service.Status -ne 'Running'){throw 'OPS_WINDOWS_TIME_TRANSITION_REVIEW'}
        $result.resyncAttempted=$true
        $sync=Invoke-PaytmTimeCommand 'Resynchronize using existing configured source' $w32tm @('/resync','/rediscover')
        $result.commands+=$sync
        $result.resyncCommandSucceeded=($null -ne $sync.exitCode -and $sync.exitCode -eq 0 -and -not $sync.failure)
        $result.commands+=Invoke-PaytmTimeCommand 'After source' $w32tm @('/query','/source')
        $result.commands+=Invoke-PaytmTimeCommand 'After status' $w32tm @('/query','/status','/verbose')
        if($result.resyncCommandSucceeded -and @($result.commands | Select-Object -Last 2 | Where-Object {$null -eq $_.exitCode -or $_.exitCode -ne 0 -or $_.failure}).Count -eq 0){$result.status='RESYNC_COMMAND_SUCCEEDED_SOURCE_AND_CLOCK_REVIEW_PENDING'}
        else{$result.failure='OPS_WINDOWS_RESYNC_OR_STATUS_FAILED'}
    }catch{
        $result.failure=if($_.Exception.Message -cmatch '^OPS_[A-Z_]+$'){$_.Exception.Message}else{'OPS_WINDOWS_TIME_SERVICE_REVIEW_REQUIRED'}
    }finally{$result.afterUtc=[DateTimeOffset]::UtcNow.ToString('o')}
    [pscustomobject]$result
}
function Assert-PaytmReviewedOperationsReport([string]$Path){
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 100000){throw 'OPS_PRIOR_REPORT_INVALID'}
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if($hash -cne '1137505E2D6CD33BDF24CBA4EBF7729AD24222973D14E5AC6A60026028067773'){throw 'OPS_PRIOR_REPORT_HASH_MISMATCH'}
    [pscustomobject]@{runId='b5f4ea70636047d6ad6ab4dc378a505f';sha256=$hash}
}
