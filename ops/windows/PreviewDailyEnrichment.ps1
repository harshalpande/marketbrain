[CmdletBinding()]
param(
    [Parameter()]
    [datetime]$TargetDate,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status); daily enrichment preview was not requested."
}
$latestBackfill = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"

$uri = "$BaseUrl/api/v1/market-data/daily-enrichment/preview"
if ($PSBoundParameters.ContainsKey('TargetDate')) {
    $dateText = $TargetDate.ToString('yyyy-MM-dd')
    $uri = "$uri`?targetDate=$([uri]::EscapeDataString($dateText))"
}

Write-Host 'Preparing the read-only daily enrichment plan...'
$preview = Invoke-RestMethod $uri

if ($preview.databaseWritesPerformed -ne $false) {
    throw 'Preview reported database writes; stop and review the backend.'
}
if ([string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Preview did not return a valid deterministic manifest hash.'
}
if ($preview.instrumentCount -lt 1) {
    throw 'Preview did not contain any matched NIFTY 500 instruments.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$artifactPath = Join-Path $OutputDirectory (
    'daily-enrichment-preview-{0}-{1}.json' -f $preview.targetDate, $preview.manifestHash
)
$preview | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifactPath -Encoding utf8

[pscustomobject]@{
    Status                     = if ($preview.blockedInstruments -eq 0) { 'REVIEW_REQUIRED' } else { 'BLOCKED' }
    UniverseSnapshotId         = $preview.universeSnapshotId
    TargetDate                 = $preview.targetDate
    InstrumentCount            = $preview.instrumentCount
    UpToDateInstruments        = $preview.upToDateInstruments
    FetchInstruments           = $preview.fetchInstruments
    BlockedInstruments         = $preview.blockedInstruments
    EarliestFromDate           = $preview.earliestFromDate
    TotalRequestedCalendarDays = $preview.totalRequestedCalendarDays
    MaximumCatchupDays         = $preview.maximumCatchupDays
    ManifestHash               = $preview.manifestHash
    DatabaseWritesPerformed    = $preview.databaseWritesPerformed
    WorkerEnabled              = $latestBackfill.workerEnabled
    FullPreviewPath            = $artifactPath
} | Format-List

$preview.instruments |
    Group-Object status |
    Select-Object Name, Count |
    Sort-Object Name |
    Format-Table -AutoSize

if ($preview.blockedInstruments -gt 0) {
    Write-Host 'Blocked instruments'
    $preview.instruments |
        Where-Object status -in @('NO_BASELINE', 'CATCHUP_LIMIT_EXCEEDED') |
        Format-Table symbol, lastStoredDate, requestedFrom, requestedTo, requestedCalendarDays, status -AutoSize
    throw 'DAILY ENRICHMENT PREVIEW BLOCKED: share this complete output; do not create or start a run.'
}
if ($latestBackfill.workerEnabled -ne $false) {
    throw 'DAILY ENRICHMENT PREVIEW BLOCKED: disable the collection worker before reviewed planning.'
}

Write-Host ''
Write-Host 'DAILY ENRICHMENT PREVIEW COMPLETE: no job, chunk, candle, finding, or resolution was written.'
Write-Host 'Share this complete output and the manifest hash for review. Do not create or start the run yet.'
