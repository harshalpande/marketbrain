#Requires -Version 7.0
[CmdletBinding()]param(
    [string]$StagingReportPath='C:\MarketBrainData\Review\paper-writer-hba-stage-20261013-183806-e7f2eb4166c8.json',
    [string]$RestrictionReportPath='C:\MarketBrainData\Review\paper-writer-restriction-20261013-121046-dbd532c96a9d.json',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [switch]$Collect
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterNetworkReview.ps1')
if ($Collect) {
    Invoke-PaperWriterNetworkCollection { param($Snapshot)
        $json=$Snapshot | ConvertTo-Json -Depth 14 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 2MB) { throw 'NETWORK_OUTPUT_LIMIT' }
        $json
    }
    exit 0 # Parent independently checks the final status, including FAILED snapshots.
}
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Assert-PaperCustodyPath $OutputDirectory; [void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-network-review-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
$watch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version='PAPER_WRITER_NETWORK_REVIEW_V1';status='RUNNING';revision=$null;manifest=@{};inputHashes=@{};events=@();snapshot=$null;process=$null;findings=@();failureCode=$null;failureLine=$null;elapsedSeconds=0;configurationChanged=$false;databaseContacted=$false;writerLoginAttempted=$false;credentialsCreated=$false;actionExecutionEnabled=$false;activationAuthorized=$false}
function Save { $report.elapsedSeconds=$watch.Elapsed.TotalSeconds; Save-NumericalHistoryReport $report $path -Compact }
function Stage([int]$Percent,[string]$Message) { $report.events+=@{percent=$Percent;message=$Message}; Save; Write-Host "[$Percent%] $Message"; Write-Progress -Activity 'Paper writer targeted network review' -Status $Message -PercentComplete $Percent }
try {
    Stage 0 'Read-only review of two saved firewall findings. No HBA reapply, credentials, database connections or network probes.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'NETWORK_WINDOWS_ADMIN_REQUIRED' }
    $dirty=@(git -C $root status --porcelain); if ($LASTEXITCODE -ne 0 -or $dirty.Count) { throw 'NETWORK_WORKTREE_REQUIRES_REVIEW' }
    $report.revision=(git -C $root rev-parse HEAD | Out-String).Trim(); if ($LASTEXITCODE -ne 0) { throw 'NETWORK_REVISION_UNAVAILABLE' }
    foreach ($name in @('GetPaperWriterNetworkReview.ps1','PaperWriterNetworkReview.ps1','NumericalHistoryEvidence.ps1','PaperWriterCustody.ps1','PaperStorageKey.ps1','PaperWriterPreflight.ps1')) { $report.manifest[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash }
    $stageHash='E540CC1DABE3C2014FCD01D01C3B4A53ABC4C608D4708F75B9CF47C83C316144'
    $scopeHash='9B1B2C9E4B3D87F8C7F6D37BD2C8798AF637A7406AB11A42DF23A841BCA9000E'
    $savedStage=Read-PaperNetworkPinnedEvidence $StagingReportPath $stageHash
    $savedScope=Read-PaperNetworkPinnedEvidence $RestrictionReportPath $scopeHash
    if ($savedStage.status -cne 'HBA_RESTRICTION_STAGED_WRITER_DISABLED' -or $savedScope.status -cne 'PREPARATION_CAPTURED_STAGING_BLOCKED') { throw 'NETWORK_INPUT_STATUS' }
    $report.inputHashes=@{staging=$stageHash;restriction=$scopeHash}
    Stage 20 'Saved evidence verified. Mapping selected rules, adapters, profiles and PostgreSQL listener metadata.'
    $native=Invoke-PaperCatalogProcess (Join-Path $PSHOME 'pwsh.exe') @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'GetPaperWriterNetworkReview.ps1'),'-Collect') $root 150
    $report.process=@{exitCode=$native.exitCode;timedOut=$native.timedOut;elapsedSeconds=$native.elapsedSeconds}
    if ($native.stdout.Length -gt 10MB) { throw 'NETWORK_CHILD_OUTPUT_LIMIT' }
    $lines=0
    foreach ($line in ($native.stdout -split '\r?\n')) {
        if (-not $line.Trim()) { continue }; $lines++
        if ($lines -gt 5 -or [Text.Encoding]::UTF8.GetByteCount($line) -gt 2MB) { throw 'NETWORK_CHILD_OUTPUT_LIMIT' }
        $value=$line | ConvertFrom-Json; Assert-PaperNetworkSnapshot $value; $report.snapshot=$value; Save
    }
    if ($native.exitCode -ne 0 -or $native.timedOut -or $null -eq $report.snapshot -or $report.snapshot.status -cne 'TARGETED_NETWORK_CAPTURED_REVIEW_REQUIRED') { throw 'NETWORK_COLLECTION_INCOMPLETE' }
    Stage 90 'Captured targeted metadata; preparing findings. Collection success does not authorize firewall changes or writer LOGIN.'
    $report.findings=@('TARGETED_TWO_RULE_REVIEW_NOT_FULL_FIREWALL_AUDIT','EXTERNAL_REACHABILITY_NOT_TESTED','NON_ATOMIC_METADATA','SAVED_HBA_SUCCESS_NOT_A_FRESH_DATABASE_CHECK','WRITER_ACTIVATION_REQUIRES_SEPARATE_APPROVAL')
    if (@($report.snapshot.missingRuleNames).Count) { $report.findings+='SAVED_RULE_NO_LONGER_PRESENT' }
    if (-not $report.snapshot.selectedRulesStableAtEnd) { $report.findings+='SELECTED_RULES_CHANGED_DURING_COLLECTION' }
    if (-not @($report.snapshot.listeners).Count) { $report.findings+='DATABASE_LISTENER_NOT_OBSERVED' }
    if (-not @($report.snapshot.firewallProfiles).Count) { $report.findings+='FIREWALL_PROFILE_METADATA_UNAVAILABLE' }
    if (@($report.snapshot.addressLinks | Where-Object { $_.status -cne 'ADDRESS_OBSERVED_ON_INTERFACE' }).Count) { $report.findings+='RULE_ADDRESS_MAPPING_REQUIRES_REVIEW' }
    foreach ($link in $report.snapshot.addressLinks) {
        foreach ($match in $link.matches) {
            if (@($match.adapters).Count -ne 1 -or @($match.connectionProfiles).Count -ne 1) { $report.findings+='INTERFACE_IDENTITY_OR_PROFILE_UNRESOLVED' }
        }
    }
    $report.findings=@($report.findings | Select-Object -Unique)
    if (@($report.snapshot.rules | Where-Object { @($_.missingFields).Count }).Count) { $report.findings+='RULE_FIELDS_UNAVAILABLE' }
    $report.status='NETWORK_REVIEW_CAPTURED_ACTIVATION_BLOCKED'
} catch {
    $report.status='FAILED'; $report.failureCode='NETWORK_REVIEW_FAILED'; $report.failureLine=$_.InvocationInfo.ScriptLineNumber
    if ($_.Exception.Message -cmatch '^NETWORK_[A-Z_]+$') { $report.failureCode=$_.Exception.Message }
} finally {
    Save; Write-Progress -Activity 'Paper writer targeted network review' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s')
    Write-Host "Share this ONE file: $path"
}
if ($report.status -ceq 'FAILED') { throw ('Network review stopped: '+$report.failureCode) }
