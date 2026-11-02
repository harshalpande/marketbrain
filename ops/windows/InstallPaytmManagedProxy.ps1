#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$SupervisorReportPath='C:\MarketBrainData\Review\paytm-supervisor-recovery-20261102-170041-a7d2909100d7409e8cec8160806195ff.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmTunnelVerification.ps1','PaytmManagedProxy.ps1')){. (Join-Path $PSScriptRoot $name)}
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;
    sourceHashes=@{};supervisorReceiptHash=$null;lockedBefore=$null;lockedAfter=$null;server=$null;serverReportText=$null;elapsedSeconds=0;
    acceptedProgress=@();windowsTaskChanged=$false;windowsTunnelStarted=$false;credentialsUsed=$false;ordersEnabled=$false}
$clock=[Diagnostics.Stopwatch]::StartNew()
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-managed-proxy-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
function Save-ManagedReport {
    $report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3)
    [IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
try {
    $f=[IO.File]::Open($path,'CreateNew','Write','Read');$f.Dispose();Save-ManagedReport
    Assert-PaytmCustodyController
    $null=Assert-PaytmAccountPath $SupervisorReportPath
    $report.supervisorReceiptHash=(Get-FileHash -LiteralPath $SupervisorReportPath).Hash
    if($report.supervisorReceiptHash -cne '865A6286E03385CC4BAE5E484DE03A7EF658FFF020BE6522192CE8E044675E2A'){throw 'MANAGED_SUPERVISOR_RECEIPT_NOT_ACCEPTED'}
    $receipt=Read-PaytmRepairJson $SupervisorReportPath 32768
    Assert-PaytmHostStatus $receipt.final $receipt.installationId
    Import-Module ScheduledTasks -ErrorAction Stop
    $report.lockedBefore=Wait-PaytmHost $receipt.installationId LOCKED
    foreach($name in @('InstallPaytmManagedProxy.ps1','PaytmManagedProxy.ps1','PaytmTunnelVerification.ps1','..\linux\InstallPaytmTunnelIdentity.sh','..\linux\StagePaytmLoopbackProxy.sh','..\linux\ManagePaytmProxyLifecycle.sh')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    $report.acceptedProgress=@(Get-PaytmReadinessProgress)
    Set-Clipboard -Value (Get-PaytmManagedProxyPayload $report.runId)
    $report.stage='AWAIT_VPS_MANAGED_INSTALL';Save-ManagedReport
    Write-Host '[20%] VPS installation command copied to the Windows clipboard.'
    Write-Host 'In verified marketbrain-admin PuTTY: run sudo -v, enter the VPS admin password locally, then paste the copied command.'
    Write-Host 'It automatically backs up proxy configuration, installs restart/disable controls, tests recovery and leaves the loopback proxy running with boot enabled on success.'
    Write-Host 'No START-TEST or SERVER_READY exchange is used. Wait for BEGIN_MANAGED_REPORT through END_MANAGED_REPORT.'
    Write-Host 'Copy that COMPLETE report block from PuTTY, then return here.'
    Write-Progress -Activity 'Managed VPS proxy' -Status 'Waiting for VPS result; real progress is displayed in PuTTY' -PercentComplete 20
    $answer=Read-Host 'When the complete VPS report block is copied, type REPORT-COPIED here'
    if($answer -cne 'REPORT-COPIED'){throw 'MANAGED_REPORT_COPY_NOT_CONFIRMED'}
    $report.stage='VERIFY_VPS_RESULT'
    $copied=Get-Clipboard -Raw
    if($copied.Length -gt 65536){throw 'MANAGED_REPORT_BOUNDARY'}
    # Retain only a bounded matching report envelope, never an unrelated clipboard.
    $envelope=[regex]::Match($copied,'(?ms)^BEGIN_MANAGED_REPORT_'+$report.runId+'\r?\n.*?^END_MANAGED_REPORT_'+$report.runId+'\r?$')
    if($envelope.Success){$report.serverReportText=$envelope.Value;Save-ManagedReport}
    $report.server=Read-PaytmManagedProxyReport $copied $report.runId;Save-ManagedReport
    Assert-PaytmManagedProxyPassed $report.server
    $report.lockedAfter=Wait-PaytmHost $receipt.installationId LOCKED
    Assert-PaytmHostAdvance $report.lockedBefore $report.lockedAfter
    $report.stage='COMPLETE';$report.status='VPS_MANAGED_PROXY_PASSED_WINDOWS_TRANSPORT_PENDING'
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(HOST|MANAGED|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'MANAGED_PROXY_REVIEW_REQUIRED'}
    $report.failureDetails=[ordered]@{exceptionType=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName);line=$_.InvocationInfo.ScriptLineNumber}
}finally{
    Save-ManagedReport;Write-Progress -Activity 'Managed VPS proxy' -Completed
    Write-Progress -Activity 'Gateway supervisor installation' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    if($report.failure){Write-Host 'The remote result determines VPS state. Do not repeat installation; retain its PuTTY report/log for review.'}
}
if($report.failure){throw 'Managed proxy needs review. Share the printed JSON and retain the VPS report.'}
