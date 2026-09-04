[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [switch]$Apply,
    [string]$ReviewedBy = '',
    [string]$ExpectedManifestHash = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reviewableStatuses = @(
    'OFFICIAL_PRICES_MATCH',
    'OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
)

$expectedCandidateKeys = @(
    'ABB|2013-05-17|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'ABFRL|2025-05-22|OFFICIAL_PRICES_MATCH'
    'ABREL|2019-10-11|OFFICIAL_PRICES_MATCH'
    'ACUTAAS|2025-01-29|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'ADANIENT|2014-04-10|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2015-06-03|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2017-04-26|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2018-09-06|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2019-05-20|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2020-08-25|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2023-02-01|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2023-02-02|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2023-02-08|OFFICIAL_PRICES_MATCH'
    'ADANIENT|2024-11-21|OFFICIAL_PRICES_MATCH'
    'ADANIGREEN|2024-11-29|OFFICIAL_PRICES_MATCH'
    'ADANIPORTS|2024-06-04|OFFICIAL_PRICES_MATCH'
    'ADANIPOWER|2018-10-10|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'ADANIPOWER|2020-03-12|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'ADANIPOWER|2021-06-07|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'ANANTRAJ|2020-08-07|OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES'
    'APOLLOTYRE|2013-06-13|OFFICIAL_PRICES_MATCH'
    'ASTERDM|2024-04-23|OFFICIAL_PRICES_MATCH'
) | Sort-Object

function Get-IsoDate {
    param([Parameter(Mandatory = $true)]$Value)
    return ([datetime]$Value).ToString('yyyy-MM-dd')
}

function Get-CandidateKey {
    param([Parameter(Mandatory = $true)]$Finding)
    return '{0}|{1}|{2}' -f $Finding.symbol, (Get-IsoDate $Finding.findingDate), $Finding.evidenceStatus
}

function Get-ResolutionKey {
    param([Parameter(Mandatory = $true)]$Resolution)
    return '{0}|{1}' -f $Resolution.symbol, (Get-IsoDate $Resolution.findingDate)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $algorithm.ComputeHash($bytes)
        return ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $algorithm.Dispose()
    }
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latest.status -ne 'COMPLETED' -or $latest.completedChunks -ne 750 -or $latest.failedChunks -ne 0) {
    throw 'The expected completed 50-instrument backfill is not active.'
}
if ($latest.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during governed review.'
}

$jobId = $latest.jobId
$beforeQuality = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$jobId"
$beforeResolutions = @(
    Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
)
$evidence = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/large-move-evidence?jobId=$jobId"

if ($evidence.findingCount -ne 28 -or
    $evidence.sourceRequestCount -ne 28 -or
    $evidence.officialMatchCount -ne 16 -or
    $evidence.officialAdjustedReturnMatchCount -ne 6 -or
    $evidence.officialMismatchCount -ne 6 -or
    $evidence.sourceUnavailableFindingCount -ne 0 -or
    $evidence.symbolNotFoundCount -ne 0 -or
    $evidence.resolutionsWritten) {
    throw 'Large-move evidence no longer matches the reviewed Step 18 classification.'
}

$candidates = @(
    $evidence.findings |
        Where-Object { $_.evidenceStatus -in $reviewableStatuses } |
        Sort-Object symbol, findingDate
)
$actualCandidateKeys = @($candidates | ForEach-Object { Get-CandidateKey $_ } | Sort-Object)
$manifestDifferences = @(
    Compare-Object -ReferenceObject $expectedCandidateKeys -DifferenceObject $actualCandidateKeys
)
if ($candidates.Count -ne 22 -or $manifestDifferences.Count -ne 0) {
    $differenceText = $manifestDifferences | Format-Table -AutoSize | Out-String
    throw "The 22-candidate manifest changed. No resolutions were written.`n$differenceText"
}

$manifestHash = Get-Sha256 ($actualCandidateKeys -join "`n")
$expectedReviewedHash = '726ab4d0cb4c697e9dd35d801ebfa87ad4bca1adb854517c994d662999eed4c1'
if ($manifestHash -ne $expectedReviewedHash) {
    throw "Manifest hash $manifestHash does not equal the reviewed code hash $expectedReviewedHash."
}

$existingLargeMoveResolutions = @(
    $beforeResolutions | Where-Object { $_.findingType -eq 'LARGE_MOVE' }
)
$existingByFinding = @{}
foreach ($resolution in $existingLargeMoveResolutions) {
    $resolutionKey = Get-ResolutionKey $resolution
    if ($existingByFinding.ContainsKey($resolutionKey)) {
        throw "More than one current resolution exists for $resolutionKey."
    }
    $existingByFinding[$resolutionKey] = $resolution
}

foreach ($candidate in $candidates) {
    $resolutionKey = '{0}|{1}' -f $candidate.symbol, (Get-IsoDate $candidate.findingDate)
    if ($existingByFinding.ContainsKey($resolutionKey) -and
        $existingByFinding[$resolutionKey].resolutionType -ne 'VERIFIED_EXCHANGE_MOVE') {
        throw "$resolutionKey already has a non-verified resolution. Revoke and review it manually."
    }
}

$pendingCandidates = @(
    $candidates | Where-Object {
        $resolutionKey = '{0}|{1}' -f $_.symbol, (Get-IsoDate $_.findingDate)
        -not $existingByFinding.ContainsKey($resolutionKey)
    }
)

[pscustomobject]@{
    Mode = $(if ($Apply) { 'APPLY' } else { 'PREVIEW_ONLY' })
    JobId = $jobId
    ManifestHash = $manifestHash
    CandidateCount = $candidates.Count
    AlreadyResolvedCandidateCount = $candidates.Count - $pendingCandidates.Count
    PendingCandidateCount = $pendingCandidates.Count
    ExistingResolutionCount = $beforeResolutions.Count
    CandlesBefore = $beforeQuality.totalCandles
    WorkerEnabled = $latest.workerEnabled
} | Format-List

$candidates |
    Select-Object symbol, findingDate, evidenceStatus, officialSymbol, matchBasis,
        storedReturnPercent, officialReturnPercent, returnDifferencePercentagePoints, sourceUrl |
    Format-Table -AutoSize

if ($beforeResolutions.Count -gt 0) {
    'Existing current resolutions:'
    $beforeResolutions |
        Format-Table findingType, symbol, findingDate, resolutionType, reviewedBy -AutoSize
}

if (-not $Apply) {
    'PREVIEW COMPLETE: no resolution or candle was written.'
    'Share this output for review before using -Apply.'
    return
}

if ([string]::IsNullOrWhiteSpace($ReviewedBy)) {
    throw 'ReviewedBy is required in apply mode.'
}
if ($ExpectedManifestHash -ne $manifestHash) {
    throw 'ExpectedManifestHash must equal the hash printed by the reviewed preview.'
}

$written = @()
foreach ($candidate in $pendingCandidates) {
    $date = Get-IsoDate $candidate.findingDate
    $basis = if ($candidate.evidenceStatus -eq 'OFFICIAL_PRICES_MATCH') {
        'Exact NSE previous-close and close prices matched.'
    } else {
        'NSE and stored prices use a consistent scale and their close-to-close returns matched within the governed tolerance.'
    }
    $notes = '{0} Official symbol={1}; match basis={2}; stored return={3}%; official return={4}%; return difference={5} percentage points.' -f `
        $basis, $candidate.officialSymbol, $candidate.matchBasis,
        $candidate.storedReturnPercent, $candidate.officialReturnPercent,
        $candidate.returnDifferencePercentagePoints
    $body = @{
        jobId = $jobId
        symbol = $candidate.symbol
        findingType = 'LARGE_MOVE'
        findingDate = $date
        relatedDate = $null
        resolutionType = 'VERIFIED_EXCHANGE_MOVE'
        evidenceSource = 'NSE official daily BhavCopy'
        evidenceUrl = $candidate.sourceUrl
        notes = $notes
        reviewedBy = $ReviewedBy.Trim()
        exclusionFrom = $null
        exclusionTo = $null
    } | ConvertTo-Json
    $written += Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/market-data/backfills/quality-resolutions" `
        -ContentType 'application/json' `
        -Body $body
}

$afterQuality = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$jobId"
$afterResolutions = @(
    Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
)

if ($afterQuality.totalCandles -ne $beforeQuality.totalCandles) {
    throw 'Candle count changed during resolution review. Stop and investigate.'
}
if ($afterQuality.unresolvedLargeMoveCount -ne 6) {
    throw "Expected 6 unresolved large moves, found $($afterQuality.unresolvedLargeMoveCount)."
}
if ($afterResolutions.Count -ne ($beforeResolutions.Count + $pendingCandidates.Count)) {
    throw 'Current resolution count did not increase by the expected pending-candidate count.'
}

[pscustomobject]@{
    Status = 'COMPLETED'
    ManifestHash = $manifestHash
    WrittenResolutionCount = $written.Count
    CurrentResolutionCountBefore = $beforeResolutions.Count
    CurrentResolutionCountAfter = $afterResolutions.Count
    CandlesBefore = $beforeQuality.totalCandles
    CandlesAfter = $afterQuality.totalCandles
    UnresolvedLargeMovesBefore = $beforeQuality.unresolvedLargeMoveCount
    UnresolvedLargeMovesAfter = $afterQuality.unresolvedLargeMoveCount
    ModelTrainingEligible = $afterQuality.modelTrainingEligible
    BacktestingEligible = $afterQuality.backtestingEligible
} | Format-List
