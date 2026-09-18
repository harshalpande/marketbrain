#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ApprovedLlmCleanup.ps1')
$runId='llm-cleanup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$plan=Get-ApprovedCleanupPlan $env:USERPROFILE $runId
$output=Assert-CleanupPath 'C:\MarketBrainData\Review'
if (-not (Test-Path -LiteralPath $output)) {[void](New-Item -ItemType Directory -Path $output)}
$path=Join-Path $output ($runId+'.json')
if (Test-Path -LiteralPath $path) {throw 'Evidence path exists; refusing overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='MARKETBRAIN_APPROVED_LLM_CLEANUP_V1';status='STARTING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    apply=[bool]$Apply;operatorConfirmed=$false;plan=$plan
    codeIdentity=@{runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'ApprovedLlmCleanup.ps1')).Hash}
    before=$null;after=$null;retainedBefore=$null;retainedAfter=$null;oldFileBefore=$null
    quarantineState='NOT_ATTEMPTED';graniteState='NOT_ATTEMPTED';observedCDriveFreeDeltaBytes=$null
    events=[Collections.Generic.List[object]]::new();errorType=$null
    recovery='Qwen 0.5B: move the recorded quarantine file back to original path only if absent, after verifying hash. Same-volume quarantine frees no disk space. Granite deletion is not locally reversible: re-download would require network and may resolve a different digest. No automatic download/rollback.'
    boundaries='No process stops, scheduler/service changes, job-status API, inference, database/broker actions, recursive deletion or cache/blob directory removal. Disk delta is observational and may include unrelated activity. Loaded-model check is a snapshot, not a global job lock; keep all model jobs idle throughout.'
}
function Save-CleanupProgress([int]$Percent,[string]$Message) {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-LlmInventoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 98 -Activity 'Approved scoped LLM cleanup' -Status $Message -PercentComplete $Percent
}
try {
    Save-CleanupProgress 0 'Preparing scoped cleanup. Default mode is preview only.'
    Write-Host "Single evidence file: $path"
    Write-Host "Granite removal: $($plan.granite) (recovery requires download)."
    Write-Host "Qwen 0.5B move: $($plan.oldFile)"
    Write-Host "Recoverable quarantine: $($plan.quarantineFile)"
    Write-Host "Keep: $($plan.retainedFile), llama.cpp, Ollama runtime, all reports and data."
    if ($Apply) {
        Write-Warning 'Proceed ONLY if all model jobs/terminals are idle and scheduled/service consumers of these old models have been reviewed. Do not start model jobs during cleanup. The stale saved RUNNING job is not automatically stopped or relabelled.'
        $answer=Read-Host 'To confirm these conditions AND approve the exact removal/quarantine, type CLEANUP GRANITE AND QWEN05; otherwise press Enter to cancel'
        if ($answer -cne 'CLEANUP GRANITE AND QWEN05') {$report.status='CANCELLED';Save-CleanupProgress 100 'Cancelled; no models changed.';return}
        $report.operatorConfirmed=$true
    }
    Invoke-ApprovedCleanup $plan $report ${function:Save-CleanupProgress} ([bool]$Apply) $report.operatorConfirmed
} catch {
    $report.status='STOPPED_REVIEW_REPORT';$report.errorType=$_.Exception.GetType().Name
    try {Save-CleanupProgress 100 'Stopped. Inspect action states: earlier actions may have succeeded; do not assume rollback.'} catch {Write-Warning 'Evidence save failed; retain previous JSON/pending files.'}
    throw
} finally {
    Write-Progress -Id 98 -Activity 'Approved scoped LLM cleanup' -Completed
    Write-Host "Share: $path"
}
