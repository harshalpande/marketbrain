[CmdletBinding()]
param(
    [string]$DatabaseHost = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int]$DatabasePort = 5432,
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_$]*$')]
    [string]$DatabaseName = 'marketbrain',
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_$]*$')]
    [string]$DatabaseUser = 'marketbrain_app',
    [string]$PostgreSqlBin = 'C:\Program Files\PostgreSQL\18\bin',
    [string]$ReviewDirectory = 'C:\MarketBrainData\Review',
    [string]$BackupDirectory = 'C:\MarketBrainData\Backups',
    [ValidateRange(1024, 1048576)]
    [long]$MinimumFreeSpaceMB = 2048,
    [string]$BaseUrl = 'http://127.0.0.1:8080'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$jobId = [guid]'30d59236-017c-406c-bc31-ef4bb1d4ee47'
$manifestHash = '9c11c15a4cf82a840cdbbd3e52cbc872b7916c405172ce5571ecab549568614c'
$planHash = 'bdf4965b15c3e35f4bdd7ee3bb1493c5bd62f517a881e632b0656c0efd9835ec'
$expectedInstruments = 190
$expectedChunks = 2190
$expectedCandles = 520018
$expectedRejectedRows = 29
$expectedFindings = 6685

function Get-RequiredFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description is missing: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-SizeMB {
    param([Parameter(Mandatory)][long]$Bytes)

    return [math]::Round($Bytes / 1MB, 2)
}

$psqlPath = Get-RequiredFile `
    -Path (Join-Path $PostgreSqlBin 'psql.exe') `
    -Description 'PostgreSQL psql executable'
$pgDumpPath = Get-RequiredFile `
    -Path (Join-Path $PostgreSqlBin 'pg_dump.exe') `
    -Description 'PostgreSQL pg_dump executable'
$pgRestorePath = Get-RequiredFile `
    -Path (Join-Path $PostgreSqlBin 'pg_restore.exe') `
    -Description 'PostgreSQL pg_restore executable'

if (-not (Test-Path -LiteralPath $ReviewDirectory -PathType Container)) {
    throw "The reviewed evidence directory is missing: $ReviewDirectory"
}

$finalDatabaseReportPath = Get-RequiredFile `
    -Path (Join-Path $ReviewDirectory "expansion-batch-4-final-database-quality-$jobId.json") `
    -Description 'Final Batch 4 database-quality report'
$finalProviderReportPath = Get-RequiredFile `
    -Path (Join-Path $ReviewDirectory "expansion-batch-4-final-provider-quality-$jobId.json") `
    -Description 'Final Batch 4 provider-quality report'
$finalCheckpointPath = Get-RequiredFile `
    -Path (Join-Path $ReviewDirectory "expansion-batch-4-final-quality-checkpoints-$jobId.json") `
    -Description 'Final Batch 4 quality checkpoint'

$finalCheckpoint = Get-Content -LiteralPath $finalCheckpointPath -Raw | ConvertFrom-Json
$providerReport = Get-Content -LiteralPath $finalProviderReportPath -Raw | ConvertFrom-Json
$providerChecks = @($providerReport.providerSpotChecks | Where-Object { $null -ne $_ })
$providerNonMatches = @($providerChecks | Where-Object { $_.status -ne 'MATCHED' })
$currentResolutions = @($providerReport.currentResolutions | Where-Object { $null -ne $_ })

if ($finalCheckpoint.status -ne 'ELIGIBLE' -or
    [guid]$finalCheckpoint.jobId -ne $jobId -or
    $finalCheckpoint.manifestHash -ne $manifestHash -or
    $finalCheckpoint.planHash -ne $planHash -or
    $finalCheckpoint.failedInvariantCount -ne 0 -or
    $finalCheckpoint.remediationOrJobCheckpointChanged -or
    $finalCheckpoint.databaseWritesPerformed -or
    [guid]$providerReport.jobId -ne $jobId -or
    $providerReport.jobStatus -ne 'COMPLETED' -or
    $providerReport.qualityStatus -ne 'PASS' -or
    $providerReport.instrumentCount -ne $expectedInstruments -or
    $providerReport.totalCandles -ne $expectedCandles -or
    $providerReport.blockingInstrumentCount -ne 0 -or
    $providerReport.missingProviderDataInstrumentCount -ne 0 -or
    $providerReport.reviewInstrumentCount -ne 0 -or
    $providerReport.duplicateRows -ne 0 -or
    $providerReport.invalidRows -ne 0 -or
    $providerReport.resolvedFindingCount -ne $expectedFindings -or
    $currentResolutions.Count -ne $expectedFindings -or
    $providerReport.unresolvedFindingCount -ne 0 -or
    $providerReport.truncatedFindingCount -ne 0 -or
    -not $providerReport.providerSpotCheckRequested -or
    $providerReport.providerMismatchCount -ne 0 -or
    $providerReport.providerCheckFailureCount -ne 0 -or
    $providerChecks.Count -ne $expectedInstruments -or
    $providerNonMatches.Count -ne 0 -or
    -not $providerReport.modelTrainingEligible -or
    -not $providerReport.backtestingEligible) {
    throw 'The saved final Batch 4 audit is not the exact reviewed eligible checkpoint.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
if ([guid]$latestBefore.jobId -ne $jobId -or
    $latestBefore.batchNumber -ne 4 -or
    $latestBefore.status -ne 'COMPLETED' -or
    $latestBefore.instruments -ne $expectedInstruments -or
    $latestBefore.totalChunks -ne $expectedChunks -or
    $latestBefore.completedChunks -ne $expectedChunks -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.acceptedRows -ne $expectedCandles -or
    $latestBefore.rejectedRows -ne $expectedRejectedRows -or
    $latestBefore.workerEnabled) {
    throw 'The live database is not the reviewed completed Batch 4 checkpoint with a disabled worker.'
}

New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
$resolvedBackupDirectory = (Resolve-Path -LiteralPath $BackupDirectory).Path
$backupDirectoryItem = Get-Item -LiteralPath $resolvedBackupDirectory
$freeSpaceMB = Get-SizeMB -Bytes $backupDirectoryItem.PSDrive.Free
if ($freeSpaceMB -lt $MinimumFreeSpaceMB) {
    throw "Only $freeSpaceMB MB is free on the backup drive; at least $MinimumFreeSpaceMB MB is required."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupStem = "marketbrain-nifty500-$timestamp"
$databaseDumpPath = Join-Path $resolvedBackupDirectory "$backupStem.dump"
$partialDatabaseDumpPath = Join-Path $resolvedBackupDirectory "$backupStem.partial.dump"
$reviewArchivePath = Join-Path $resolvedBackupDirectory "$backupStem-review.zip"
$partialReviewArchivePath = Join-Path $resolvedBackupDirectory "$backupStem-review.partial.zip"
$manifestPath = Join-Path $resolvedBackupDirectory "$backupStem-manifest.json"
$logPath = Join-Path $resolvedBackupDirectory "$backupStem.log"

$plannedPaths = @(
    $databaseDumpPath,
    $partialDatabaseDumpPath,
    $reviewArchivePath,
    $partialReviewArchivePath,
    $manifestPath,
    $logPath
)
if (@($plannedPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0) {
    throw 'One or more timestamped backup paths already exist. Wait one second and run the command again.'
}

$reviewBytes = [long](
    Get-ChildItem -LiteralPath $ReviewDirectory -File -Recurse |
        Measure-Object -Property Length -Sum
).Sum

$previousPgPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
$securePassword = $null
$plainPassword = $null
$transcriptStarted = $false
$backupFailure = $null
$databaseBytes = 0L
$restoreEntryCount = 0
$reviewArchiveEntryCount = 0

try {
    Start-Transcript -Path $logPath -Force | Out-Host
    $transcriptStarted = $true

    if ([string]::IsNullOrEmpty($previousPgPassword)) {
        $securePassword = Read-Host 'Enter the PostgreSQL marketbrain_app password' -AsSecureString
        $plainPassword = [System.Net.NetworkCredential]::new('', $securePassword).Password
        if ([string]::IsNullOrEmpty($plainPassword)) {
            throw 'The PostgreSQL password cannot be empty.'
        }
        [Environment]::SetEnvironmentVariable('PGPASSWORD', $plainPassword, 'Process')
    }

    Write-Host 'Measuring the live MarketBrain database...'
    $databaseSizeOutput = @(
        & $psqlPath `
            '--no-psqlrc' `
            '--no-password' `
            '--tuples-only' `
            '--no-align' `
            '--host' $DatabaseHost `
            '--port' ([string]$DatabasePort) `
            '--username' $DatabaseUser `
            '--dbname' $DatabaseName `
            '--command' "SELECT pg_database_size('$DatabaseName');"
    )
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed while measuring the database (exit code $LASTEXITCODE)."
    }
    $databaseBytes = [long](($databaseSizeOutput -join '').Trim())

    Write-Host "Creating compressed PostgreSQL dump: $databaseDumpPath"
    & $pgDumpPath `
        '--no-password' `
        '--format=custom' `
        '--compress=9' `
        '--no-owner' `
        '--no-privileges' `
        '--host' $DatabaseHost `
        '--port' ([string]$DatabasePort) `
        '--username' $DatabaseUser `
        '--dbname' $DatabaseName `
        '--file' $partialDatabaseDumpPath
    if ($LASTEXITCODE -ne 0) {
        throw "pg_dump failed (exit code $LASTEXITCODE)."
    }
    if (-not (Test-Path -LiteralPath $partialDatabaseDumpPath -PathType Leaf) -or
        (Get-Item -LiteralPath $partialDatabaseDumpPath).Length -le 0) {
        throw 'pg_dump returned success but did not create a non-empty dump file.'
    }

    Write-Host 'Validating the PostgreSQL dump catalogue...'
    $restoreCatalogue = @(& $pgRestorePath '--list' $partialDatabaseDumpPath)
    if ($LASTEXITCODE -ne 0 -or $restoreCatalogue.Count -eq 0) {
        throw "pg_restore could not read the new dump catalogue (exit code $LASTEXITCODE)."
    }
    $restoreEntryCount = $restoreCatalogue.Count

    Write-Host "Archiving reviewed evidence: $reviewArchivePath"
    Compress-Archive `
        -LiteralPath $ReviewDirectory `
        -DestinationPath $partialReviewArchivePath `
        -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($partialReviewArchivePath)
    try {
        $reviewArchiveEntryCount = $zip.Entries.Count
    } finally {
        $zip.Dispose()
    }
    if ($reviewArchiveEntryCount -eq 0) {
        throw 'The review archive was created but contains no files.'
    }

    Move-Item -LiteralPath $partialDatabaseDumpPath -Destination $databaseDumpPath
    Move-Item -LiteralPath $partialReviewArchivePath -Destination $reviewArchivePath

    $latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
    if ($latestAfter.jobId -ne $latestBefore.jobId -or
        $latestAfter.status -ne $latestBefore.status -or
        $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
        $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
        $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
        $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
        $latestAfter.workerEnabled) {
        throw 'The Batch 4 job checkpoint changed while the backup was being created.'
    }

    Write-Host 'Both backup archives were created and validated successfully.'
} catch {
    $backupFailure = $_
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Host
    }

    [Environment]::SetEnvironmentVariable('PGPASSWORD', $previousPgPassword, 'Process')
    $plainPassword = $null
    $securePassword = $null
}

if ($null -ne $backupFailure) {
    foreach ($partialPath in @($partialDatabaseDumpPath, $partialReviewArchivePath)) {
        if (Test-Path -LiteralPath $partialPath -PathType Leaf) {
            Remove-Item -LiteralPath $partialPath -Force
        }
    }
    throw $backupFailure
}

$databaseDump = Get-Item -LiteralPath $databaseDumpPath
$reviewArchive = Get-Item -LiteralPath $reviewArchivePath
$databaseHash = (Get-FileHash -LiteralPath $databaseDumpPath -Algorithm SHA256).Hash.ToLowerInvariant()
$reviewHash = (Get-FileHash -LiteralPath $reviewArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$logHash = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
$combinedBackupBytes = $databaseDump.Length + $reviewArchive.Length

$manifest = [ordered]@{
    createdAt = [DateTimeOffset]::Now
    status = 'VERIFIED'
    dataset = 'NIFTY_500_REVIEWED_THROUGH_2026-09-01'
    database = $DatabaseName
    databaseHost = $DatabaseHost
    databasePort = $DatabasePort
    finalBatchJobId = $jobId
    finalBatchManifestHash = $manifestHash
    finalBatchPlanHash = $planHash
    finalQualityStatus = $providerReport.qualityStatus
    modelTrainingEligible = [bool]$providerReport.modelTrainingEligible
    backtestingEligible = [bool]$providerReport.backtestingEligible
    databaseSourceBytes = $databaseBytes
    reviewSourceBytes = $reviewBytes
    databaseDump = [ordered]@{
        path = $databaseDumpPath
        bytes = $databaseDump.Length
        sha256 = $databaseHash
        restoreCatalogueEntryCount = $restoreEntryCount
    }
    reviewArchive = [ordered]@{
        path = $reviewArchivePath
        bytes = $reviewArchive.Length
        sha256 = $reviewHash
        archiveEntryCount = $reviewArchiveEntryCount
    }
    log = [ordered]@{
        path = $logPath
        sha256 = $logHash
    }
    combinedBackupBytes = $combinedBackupBytes
    databaseWritesPerformed = $false
}
$manifest | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    Status = 'VERIFIED'
    Dataset = $manifest.dataset
    DatabaseSourceMB = Get-SizeMB -Bytes $databaseBytes
    ReviewSourceMB = Get-SizeMB -Bytes $reviewBytes
    DatabaseDumpMB = Get-SizeMB -Bytes $databaseDump.Length
    ReviewArchiveMB = Get-SizeMB -Bytes $reviewArchive.Length
    CombinedBackupMB = Get-SizeMB -Bytes $combinedBackupBytes
    FreeSpaceBeforeMB = $freeSpaceMB
    DatabaseSha256 = $databaseHash
    ReviewArchiveSha256 = $reviewHash
    DatabaseDumpPath = $databaseDumpPath
    ReviewArchivePath = $reviewArchivePath
    ManifestPath = $manifestPath
    LogPath = $logPath
    DatabaseWritesPerformed = $false
} | Format-List

Write-Host ''
Write-Host 'MARKETBRAIN BACKUP COMPLETE: the database dump and reviewed evidence archive are readable and SHA-256 recorded.'
Write-Host 'Keep all four files together. A separate restore drill is still required before this backup is considered disaster-recovery tested.'
