#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ReviewDirectory='C:\MarketBrainData\Review',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OllamaBaseUrl='http://127.0.0.1:11434'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmDependencyReview.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
$ollama=Assert-LlmInventoryLoopback $OllamaBaseUrl
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not (Test-Path -LiteralPath $OutputDirectory)) {[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('llm-dependencies-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if (Test-Path -LiteralPath $path) {throw 'Report already exists; refusing to overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='MARKETBRAIN_LLM_DEPENDENCY_REVIEW_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    powershellVersion=$PSVersionTable.PSVersion.ToString()
    codeIdentity=[ordered]@{runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'LlmDependencyReview.ps1')).Hash;inventoryHelperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')).Hash}
    sections=[ordered]@{};timingsSeconds=[ordered]@{};warnings=[Collections.Generic.List[string]]::new();events=[Collections.Generic.List[object]]::new()
    cleanupAuthorized=$false;clearance='NOT_CLEARED_REQUIRES_OPERATOR_REVIEW'
    safety=[pscustomobject]@{inferenceCalls=0;modelsDeleted=0;processesStopped=0;jobStatusApiCalls=0;downloadsPerformed=$false;onlyWrites='This report and transient atomic-save files'}
}
function Save-DependencyProgress([int]$Percent,[string]$Message) {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-LlmInventoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 97 -Activity 'Read-only LLM dependency review' -Status $Message -PercentComplete $Percent
}
try {
    Save-DependencyProgress 0 'Reading dependency hints only; no model or cleanup work.'
    Write-Host "Single evidence report: $path"
    Invoke-LlmInventoryStage $report 'health' {Get-LlmDependencyHealth $base}
    Save-DependencyProgress 15 'Service health checked; health does not prove jobs are idle.'
    Invoke-LlmInventoryStage $report 'processes' { @(Get-LlmDependencyProcesses) }
    Invoke-LlmInventoryStage $report 'ollama' { @(Get-LlmInventoryOllama $ollama 10) }
    Save-DependencyProgress 35 'Process names and installed/loaded models collected.'
    Invoke-LlmInventoryStage $report 'scheduledTasks' {Get-LlmDependencyTasks}
    Save-DependencyProgress 55 'Scheduled-task token hints collected; no commands exported.'
    Invoke-LlmInventoryStage $report 'persistedJobs' {Get-LlmDependencyEvidence $ReviewDirectory}
    Save-DependencyProgress 80 'Bounded saved-job scan complete; no job status API called.'
    Invoke-LlmInventoryStage $report 'references' {Get-LlmInventoryReferences $repo}
    $report.warnings.Add('No global read-only Java job-list API exists. Confirm all model-run terminals/Java jobs and planned experiments are idle before any removal; persisted RUNNING can be stale.')
    $report.warnings.Add('Confirm ReviewDirectory matches the deployed review volume. Actual container configuration, indirect scripts, Windows services and external schedulers remain unverified; no .env or Docker environment was exported.')
    $report.warnings.Add('No report grants deletion approval. Review UNKNOWN/partial sections and task/process matches; retain evidence, databases, volumes, llama.cpp and Qwen 1.5B.')
    $report.status='COMPLETED_REVIEW_REQUIRED'
    Save-DependencyProgress 100 'Review complete; cleanup remains NOT CLEARED.'
    Write-Host "Share only: $path"
} catch {
    $report.status='FAILED_PARTIAL_REPORT';$report.warnings.Add('Stopped: '+$_.Exception.GetType().Name)
    try {Save-LlmInventoryReport $report $path} catch {Write-Warning 'Save failed; retain the previous report/pending file.'}
    throw
} finally {Write-Progress -Id 97 -Activity 'Read-only LLM dependency review' -Completed}
