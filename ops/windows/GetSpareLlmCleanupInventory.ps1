#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [string]$OllamaBaseUrl='http://127.0.0.1:11434',
    [string[]]$AdditionalModelDirectories=@(),
    [ValidateRange(1,30)][int]$RequestTimeoutSeconds=10,
    [ValidateRange(1,120)][int]$ScanSeconds=30,
    [ValidateRange(1,50000)][int]$MaxScanEntries=10000
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$validatedBase=Assert-LlmInventoryLoopback $OllamaBaseUrl
$repository=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runId='llm-inventory-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)
if (-not (Test-Path -LiteralPath $OutputDirectory)) { [void](New-Item -ItemType Directory -Path $OutputDirectory) }
$outputRoot=(Resolve-Path -LiteralPath $OutputDirectory).Path
$reportPath=Join-Path $outputRoot ($runId+'.json')
if (Test-Path -LiteralPath $reportPath) { throw 'Unique report path already exists; refusing to overwrite.' }
$clock=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='MARKETBRAIN_LLM_CLEANUP_INVENTORY_V1';runId=$runId;status='RUNNING'
    createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    powershellVersion=$PSVersionTable.PSVersion.ToString();repositoryDirectory=$repository
    codeIdentity=[ordered]@{
        runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        collectorsSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1') -Algorithm SHA256).Hash
    }
    sections=[ordered]@{};timingsSeconds=[ordered]@{};warnings=[Collections.Generic.List[string]]::new()
    events=[Collections.Generic.List[object]]::new()
    safety=[pscustomobject]@{modelInferenceCalls=0;downloadsPerformed=$false;modelsDeleted=0;existingProcessesStopped=0;databaseWritesPerformed=$false;ordersCreated=0;onlyWrites='This uniquely named report and transient atomic-save files'}
    cleanupDecision='NOT_AUTHORIZED: inventory for review only; no automatic keep/delete recommendation'
    limitations='Known roots and local Ollama only; partial results and stopped services do not mean no installed models. No live job/service configuration verification. Review local path/model names before sharing.'
}
function Save-InventoryProgress([int]$Percent,[string]$Message) {
    $report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-LlmInventoryReport $report $reportPath
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 96 -Activity 'Read-only spare LLM inventory' -Status $Message -PercentComplete $Percent
}
try {
    Save-InventoryProgress 0 'Starting read-only inventory; no inference, downloads, deletion or process stops.'
    Write-Host "Share this single report: $reportPath"
    Invoke-LlmInventoryStage $report 'runtimes' { Get-LlmInventoryRuntime }
    Save-InventoryProgress 20 'Runtime file versions and running model processes inspected.'
    Invoke-LlmInventoryStage $report 'ollama' { @(Get-LlmInventoryOllama $validatedBase $RequestTimeoutSeconds) }
    foreach ($item in @(Get-LlmInventoryField $report.sections['ollama'] 'data')) {
        if ($null -eq $item) { continue }
        if ($item.status -ne 'AVAILABLE') { $report.warnings.Add('Ollama '+$item.endpoint+' unavailable/invalid; installed or loaded models remain unknown.') }
    }
    Save-InventoryProgress 40 'Ollama installed/loaded lists requested using local read-only endpoints.'
    Invoke-LlmInventoryStage $report 'hardware' { Get-LlmInventoryHardware }
    Save-InventoryProgress 55 'RAM, CPU, reported GPU and local disk information inspected.'
    $roots=[Collections.Generic.List[string]]::new()
    if ($env:USERPROFILE) {
        $roots.Add((Join-Path $env:USERPROFILE '.cache/huggingface/hub'))
        $roots.Add((Join-Path $env:USERPROFILE '.cache/llama.cpp'))
    }
    if ($env:LOCALAPPDATA) { $roots.Add((Join-Path $env:LOCALAPPDATA 'llama.cpp')) }
    $roots.Add('C:\MarketBrainTools\llama.cpp')
    foreach ($root in $AdditionalModelDirectories) { $roots.Add($root) }
    Invoke-LlmInventoryStage $report 'ggufFiles' { Get-LlmInventoryFiles $roots.ToArray() $MaxScanEntries 10 $ScanSeconds }
    if ($report.sections['ggufFiles'].status -eq 'COLLECTED' -and $report.sections['ggufFiles'].data.partial) { $report.warnings.Add('GGUF scan partial: inspect limits, access errors or skipped directory links before cleanup.') }
    Save-InventoryProgress 80 'Bounded known-directory GGUF scan complete; models not loaded or hashed.'
    Invoke-LlmInventoryStage $report 'referenceHints' { Get-LlmInventoryReferences $repository }
    $report.warnings.Add('Active Java jobs, scheduled tasks, nonstandard caches and actual service dependencies need follow-up before any removal.')
    $report.status='COMPLETED_REVIEW_REQUIRED'
    Save-InventoryProgress 100 'Inventory complete. Review unknown/partial sections; cleanup remains unauthorized.'
    Write-Host "Elapsed: $($clock.Elapsed). Share only: $reportPath"
} catch {
    $report.status='FAILED_PARTIAL_REPORT'
    $report.warnings.Add('Inventory stopped: '+$_.Exception.GetType().Name+'. No cleanup performed.')
    try { Save-LlmInventoryReport $report $reportPath } catch { Write-Warning 'Report save failed; inspect the previously saved report/pending file.' }
    throw
} finally { Write-Progress -Id 96 -Activity 'Read-only spare LLM inventory' -Completed }
