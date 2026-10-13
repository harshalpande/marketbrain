#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$ReviewedPlanPath,
    [Parameter(Mandatory)][string]$RecoveryDirectory,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
foreach($file in @('NumericalHistoryEvidence.ps1','PaperWriterCustody.ps1','PaperWriterRestriction.ps1','PaperWriterAccessReview.ps1','PaperWriterHbaPlan.ps1','PaperWriterHbaStage.ps1')){. (Join-Path $PSScriptRoot $file)}
$id=[Guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$held=$false;$mutex=$null
$out=Assert-PaperCustodyPath $OutputDirectory;[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-hba-recovery-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$report=[ordered]@{version='PAPER_HBA_RECOVERY_V1';status='RUNNING';recoveryStatus=$null;failureCode=$null;connectionsReverified=$false;databaseContacted=$false;databaseWritesPerformed=$false;firewallChanged=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
try {
    Write-Host '[0%] Local file recovery only. No database password, service restart or writer activation.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'HBA_STAGE_WINDOWS_ADMIN_REQUIRED'}
    $mutex=[Threading.Mutex]::new($false,'Global\MarketBrainPaperHbaRestrictionV1')
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw 'HBA_STAGE_ANOTHER_RUN_ACTIVE'}
    $accepted=Read-PaperHbaAcceptedPlan $ReviewedPlanPath
    $dir=Assert-PaperCustodyPath $RecoveryDirectory
    if($dir -cnotmatch '^C:\\MarketBrainData\\Secrets\\PaperWriterHba\\[a-f0-9]{32}$'){throw 'HBA_STAGE_RECOVERY_DIRECTORY_INVALID'}
    $j=Read-PaperHbaBackup $dir
    if($j.target -ine $accepted.metadata.hbaPath.Replace('/','\') -or $j.originalHash -cne $accepted.filePlan.originalHash -or $j.candidateHash -cne $accepted.filePlan.candidateHash -or $j.aclFingerprint -cne $accepted.filePlan.aclFingerprint){throw 'HBA_STAGE_RECOVERY_PLAN_MISMATCH'}
    if((Read-Host 'Type RESTORE ORIGINAL HBA to restore only the owned candidate file') -cne 'RESTORE ORIGINAL HBA'){throw 'HBA_STAGE_RECOVERY_NOT_CONFIRMED'}
    Write-Host '[50%] Validating backup, current bytes and permissions before recovery.'
    $report.recoveryStatus=Restore-PaperHbaBackup $dir
    $report.hbaChanged=($report.recoveryStatus -ceq 'ORIGINAL_RESTORED')
    $report.status='ORIGINAL_FILE_VERIFIED_CONNECTION_RECHECK_REQUIRED'
}catch {
    $report.status='RECOVERY_REVIEW_REQUIRED';$report.failureCode='HBA_STAGE_RECOVERY_FAILED'
    if($_.Exception.Message -cmatch '^(HBA_STAGE|HBA_PLAN|RESTRICTION|CUSTODY)_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
}finally {
    if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
    Write-Host ('[100%] '+$report.status);Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'RECOVERY_REVIEW_REQUIRED'){throw $report.failureCode}
