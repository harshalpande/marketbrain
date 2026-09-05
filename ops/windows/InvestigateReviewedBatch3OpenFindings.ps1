[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$JobId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedPlanHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Net.Http

$batchNumber = 3
$expectedInstrumentCount = 200
$expectedTotalChunks = 2320
$expectedAcceptedRows = 550050
$expectedRejectedRows = 6
$expectedUnresolvedFindings = 7036
$expectedKeepOpenCount = 10
$expectedSourceFailureCount = 4
$normalizedManifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$normalizedPlanHash = $ReviewedPlanHash.Trim().ToLowerInvariant()
$analysisPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-analysis-$JobId.json"
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"

$expectedOpenKeys = @(
    'LARGE_MOVE|CGCL|2011-11-28|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|CGCL|2012-08-07|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|COFORGE|2020-03-23|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|COFORGE|2020-03-25|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|DELHIVERY|2016-03-08|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|LTFOODS|2013-08-20|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'PEER_CONFIRMED_SESSION|DELHIVERY|2020-07-13|INVALID_SOURCE_ARCHIVE'
    'PEER_CONFIRMED_SESSION|HOMEFIRST|2020-07-13|INVALID_SOURCE_ARCHIVE'
    'PEER_CONFIRMED_SESSION|KFINTECH|2020-07-13|INVALID_SOURCE_ARCHIVE'
    'PEER_CONFIRMED_SESSION|LATENTVIEW|2020-07-13|INVALID_SOURCE_ARCHIVE'
) | Sort-Object

$archiveExpectations = @(
    [pscustomobject]@{ Date = [datetime]'2011-11-28'; Symbol = 'MMFSL'; Isin = 'INE180C01018'; CurrentSymbol = 'CGCL' }
    [pscustomobject]@{ Date = [datetime]'2012-08-07'; Symbol = 'MMFSL'; Isin = 'INE180C01018'; CurrentSymbol = 'CGCL' }
    [pscustomobject]@{ Date = [datetime]'2013-08-20'; Symbol = 'DAAWAT'; Isin = 'INE818H01012'; CurrentSymbol = 'LTFOODS' }
    [pscustomobject]@{ Date = [datetime]'2020-03-23'; Symbol = 'NIITTECH'; Isin = 'INE591G01017'; CurrentSymbol = 'COFORGE' }
    [pscustomobject]@{ Date = [datetime]'2020-03-25'; Symbol = 'NIITTECH'; Isin = 'INE591G01017'; CurrentSymbol = 'COFORGE' }
)

$identityEvidence = @(
    [pscustomobject]@{
        CurrentSymbol = 'CGCL'
        AliasSymbol = 'MMFSL'
        AliasIsin = 'INE180C01018'
        EffectiveFrom = '2011-11-28'
        EffectiveTo = '2012-08-07'
        IdentityEvidenceUrl = 'https://nsearchives.nseindia.com/content/press/28102010.htm'
        LineageEvidenceUrl = 'https://nsearchives.nseindia.com/corporate/CGCL_10042026153109_CGCL_NewspaperAdvt_IssueOpening_NCDPI.pdf'
    }
    [pscustomobject]@{
        CurrentSymbol = 'COFORGE'
        AliasSymbol = 'NIITTECH'
        AliasIsin = 'INE591G01017'
        EffectiveFrom = '2020-03-23'
        EffectiveTo = '2020-03-25'
        IdentityEvidenceUrl = 'https://nsearchives.nseindia.com/corporate/COFORGE_16112021040103_SEIntimation.pdf'
        LineageEvidenceUrl = 'https://nsearchives.nseindia.com/corporate/COFORGE_16112021040103_SEIntimation.pdf'
    }
    [pscustomobject]@{
        CurrentSymbol = 'LTFOODS'
        AliasSymbol = 'DAAWAT'
        AliasIsin = 'INE818H01012'
        EffectiveFrom = '2013-08-20'
        EffectiveTo = '2013-08-20'
        IdentityEvidenceUrl = 'https://nsearchives.nseindia.com/content/circulars/CML59161.pdf'
        LineageEvidenceUrl = 'https://nsearchives.nseindia.com/content/circulars/CML59161.pdf'
    }
)

function Get-IsoDate {
    param([Parameter(Mandatory)]$Value)
    return ([datetime]$Value).ToString('yyyy-MM-dd')
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ($algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $algorithm.Dispose()
    }
}

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    return Get-Sha256Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-CurrentResolutions {
    param(
        [Parameter(Mandatory)][string]$ApiBaseUrl,
        [Parameter(Mandatory)][guid]$BackfillJobId
    )

    $response = Invoke-RestMethod `
        "$ApiBaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$BackfillJobId" `
        -TimeoutSec 60
    return @($response | Where-Object { $null -ne $_ })
}

function Get-NseArchiveEvidence {
    param(
        [Parameter(Mandatory)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory)][datetime]$TradingDate
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $year = $TradingDate.ToString('yyyy', $culture)
    $month = $TradingDate.ToString('MMM', $culture).ToUpperInvariant()
    $stamp = $TradingDate.ToString('ddMMMyyyy', $culture).ToUpperInvariant()
    $sourceUrl = "https://archives.nseindia.com/content/historical/EQUITIES/$year/$month/cm${stamp}bhav.csv.zip"
    $archiveBytes = $Client.GetByteArrayAsync($sourceUrl).GetAwaiter().GetResult()
    if ($archiveBytes.Length -eq 0 -or $archiveBytes.Length -gt 20MB) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) was empty or exceeded the 20 MB safety limit."
    }

    $memory = [System.IO.MemoryStream]::new($archiveBytes)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $memory,
        [System.IO.Compression.ZipArchiveMode]::Read
    )
    try {
        $entries = @($archive.Entries | Where-Object { $_.Name.EndsWith('.csv', [System.StringComparison]::OrdinalIgnoreCase) })
        if ($entries.Count -ne 1) {
            throw "NSE archive for $(Get-IsoDate $TradingDate) did not contain exactly one CSV file."
        }
        $csvEntryName = $entries[0].Name
        $reader = [System.IO.StreamReader]::new($entries[0].Open(), [System.Text.Encoding]::UTF8)
        try {
            $csvText = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $archive.Dispose()
        $memory.Dispose()
    }

    $rows = @($csvText | ConvertFrom-Csv)
    if ($rows.Count -eq 0) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) contained no CSV rows."
    }
    $headerNames = @($rows[0].PSObject.Properties.Name)
    $dateColumn = if ($headerNames -contains 'TIMESTAMP') { 'TIMESTAMP' } elseif ($headerNames -contains 'TradDt') { 'TradDt' } else { $null }
    if ($null -eq $dateColumn -or -not ($headerNames -contains 'SYMBOL')) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) has an unexpected CSV layout."
    }
    $supportedRows = @($rows | Where-Object { $_.SERIES -in @('EQ', 'BE', 'BZ') })
    if ($supportedRows.Count -eq 0) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) contained no supported cash-equity rows."
    }

    return [pscustomobject]@{
        TradingDate = Get-IsoDate $TradingDate
        SourceUrl = $sourceUrl
        ArchiveSha256 = Get-Sha256Bytes $archiveBytes
        CsvEntry = $csvEntryName
        RowCount = $rows.Count
        SupportedCashRowCount = $supportedRows.Count
        DateColumn = $dateColumn
        RawDateValues = @($supportedRows | ForEach-Object { [string]$_.$dateColumn } | Sort-Object -Unique)
        Rows = $supportedRows
    }
}

function Get-OfficialRow {
    param(
        [Parameter(Mandatory)]$Archive,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][string]$Isin
    )
    $matches = @($Archive.Rows | Where-Object {
        $_.SYMBOL -eq $Symbol -and $_.ISIN -eq $Isin -and $_.SERIES -in @('EQ', 'BE', 'BZ')
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $Symbol/$Isin row on $($Archive.TradingDate), found $($matches.Count)."
    }
    $row = $matches[0]
    return [pscustomobject]@{
        CurrentSymbol = $null
        TradingDate = $Archive.TradingDate
        OfficialSymbol = $row.SYMBOL
        OfficialIsin = $row.ISIN
        Series = $row.SERIES
        PreviousClose = $row.PREVCLOSE
        Open = $row.OPEN
        High = $row.HIGH
        Low = $row.LOW
        Close = $row.CLOSE
        Volume = $row.TOTTRDQTY
        RawDate = [string]$row.($Archive.DateColumn)
        SourceUrl = $Archive.SourceUrl
        ArchiveSha256 = $Archive.ArchiveSha256
    }
}

if (-not (Test-Path -LiteralPath $analysisPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $creationPath -PathType Leaf)) {
    throw 'The reviewed Batch 3 creation report or Step 38 analysis file is missing.'
}

$analysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$creation = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$items = @($analysis.items | Where-Object { $null -ne $_ })
$openItems = @($items | Where-Object { $null -eq $_.recommendedResolutionType })
$actualOpenKeys = @($openItems | ForEach-Object {
    '{0}|{1}|{2}|{3}' -f $_.findingType, $_.symbol, (Get-IsoDate $_.findingDate), $_.analysisStatus
} | Sort-Object)
$openDifferences = @(Compare-Object -ReferenceObject $expectedOpenKeys -DifferenceObject $actualOpenKeys)

if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.planHash -ne $normalizedPlanHash -or
    $analysis.unresolvedFindingCount -ne $expectedUnresolvedFindings -or
    $analysis.keepOpenCount -ne $expectedKeepOpenCount -or
    $analysis.sourceFailureCount -ne $expectedSourceFailureCount -or
    $analysis.analysisComplete -or
    $items.Count -ne $expectedUnresolvedFindings -or
    $openItems.Count -ne $expectedKeepOpenCount -or
    $openDifferences.Count -ne 0 -or
    $analysis.candlesWritten -or
    $analysis.resolutionsWritten -or
    $creation.reviewedManifestHash -ne $normalizedManifestHash -or
    [guid]$creation.verifiedStatus.jobId -ne $JobId) {
    throw 'The saved files do not contain the exact reviewed incomplete Batch 3 plan and its ten open findings.'
}

$delhiveryManifestRows = @($creation.livePreview.instruments | Where-Object { $_.symbol -eq 'DELHIVERY' })
if ($delhiveryManifestRows.Count -ne 1 -or
    (Get-IsoDate $delhiveryManifestRows[0].nseReportedListedOn) -ne '2022-05-24') {
    throw 'The reviewed Batch 3 manifest does not contain the expected NSE DELHIVERY listing date.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}
$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
$qualityBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" -TimeoutSec 1800
$resolutionsBefore = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
if ([guid]$latestBefore.jobId -ne $JobId -or
    $latestBefore.batchNumber -ne $batchNumber -or
    $latestBefore.status -ne 'COMPLETED' -or
    $latestBefore.instruments -ne $expectedInstrumentCount -or
    $latestBefore.totalChunks -ne $expectedTotalChunks -or
    $latestBefore.completedChunks -ne $expectedTotalChunks -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.acceptedRows -ne $expectedAcceptedRows -or
    $latestBefore.rejectedRows -ne $expectedRejectedRows -or
    $latestBefore.workerEnabled -or
    $qualityBefore.unresolvedFindingCount -ne $expectedUnresolvedFindings -or
    $resolutionsBefore.Count -ne 0) {
    throw 'The live database is not the exact reviewed pre-correction Batch 3 checkpoint.'
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromMinutes(5)
$client.DefaultRequestHeaders.UserAgent.ParseAdd(
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MarketBrain/0.1 evidence-verifier'
)
$client.DefaultRequestHeaders.Referrer = [uri]'https://www.nseindia.com/all-reports'
$client.DefaultRequestHeaders.Accept.Add(
    [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/octet-stream')
)
try {
    Write-Host 'Downloading seven immutable NSE daily archives for all ten open Batch 3 findings...'
    $archiveDates = @($archiveExpectations.Date + [datetime]'2016-03-08' + [datetime]'2020-07-13' | Sort-Object -Unique)
    $archives = @{}
    foreach ($date in $archiveDates) {
        $archive = Get-NseArchiveEvidence -Client $client -TradingDate $date
        $archives[$archive.TradingDate] = $archive
    }
} finally {
    $client.Dispose()
}

$officialRows = @()
foreach ($expected in $archiveExpectations) {
    $dateKey = Get-IsoDate $expected.Date
    $officialRow = Get-OfficialRow -Archive $archives[$dateKey] -Symbol $expected.Symbol -Isin $expected.Isin
    $officialRow.CurrentSymbol = $expected.CurrentSymbol
    $officialRows += $officialRow
}

$legacyArchive = $archives['2020-07-13']
if ($legacyArchive.RawDateValues.Count -ne 1 -or $legacyArchive.RawDateValues[0] -ne '13-Jul-20') {
    throw 'The 13 July 2020 archive no longer exhibits the reviewed two-digit-year date representation.'
}

$delhiveryArchive = $archives['2016-03-08']
$delhiveryOfficialRows = @($delhiveryArchive.Rows | Where-Object {
    $_.SYMBOL -eq 'DELHIVERY' -or $_.ISIN -eq 'INE148O01028'
})
if ($delhiveryOfficialRows.Count -ne 0) {
    throw 'The 8 March 2016 official archive unexpectedly contains the later-listed DELHIVERY identity.'
}

$archiveSummaries = @($archives.Values | Sort-Object TradingDate | ForEach-Object {
    [pscustomobject]@{
        TradingDate = $_.TradingDate
        SourceUrl = $_.SourceUrl
        ArchiveSha256 = $_.ArchiveSha256
        CsvEntry = $_.CsvEntry
        RowCount = $_.RowCount
        SupportedCashRowCount = $_.SupportedCashRowCount
        DateColumn = $_.DateColumn
        RawDateValues = $_.RawDateValues
    }
})

$recommendedChanges = [pscustomobject]@{
    Parser = [pscustomobject]@{
        FindingCount = 4
        FindingDate = '2020-07-13'
        Cause = 'VALID_NSE_LEGACY_TWO_DIGIT_YEAR_NOT_SUPPORTED'
        Change = 'Parse legacy NSE dd-MMM-yy dates with an explicit 2000-based reduced year.'
        ExpectedOutcome = 'Four peer-confirmed findings become evidence-backed one-session feature exclusions.'
    }
    HistoricalIdentityAliases = $identityEvidence
    PrelistingExclusion = [pscustomobject]@{
        Symbol = 'DELHIVERY'
        FindingDate = '2016-03-08'
        OfficialListedOn = '2022-05-24'
        OfficialIsin = 'INE148O01028'
        EvidenceUrl = 'https://nsearchives.nseindia.com/corporate/DELHIVERY_08082024180744_Notice_AnnualReport_Signed.pdf'
        ExpectedOutcome = 'Exclude the one pre-listing feature date; do not invent or rewrite a candle.'
    }
}

$canonicalEvidence = @(
    "job=$JobId"
    "manifest=$normalizedManifestHash"
    "plan=$normalizedPlanHash"
    $archiveSummaries | ForEach-Object { "archive=$($_.TradingDate)|$($_.ArchiveSha256)|$($_.RawDateValues -join ',')" }
    $officialRows | ForEach-Object { "identity=$($_.CurrentSymbol)|$($_.TradingDate)|$($_.OfficialSymbol)|$($_.OfficialIsin)" }
    $identityEvidence | ForEach-Object { "alias=$($_.CurrentSymbol)|$($_.AliasSymbol)|$($_.AliasIsin)|$($_.EffectiveFrom)|$($_.EffectiveTo)" }
    'prelisting=DELHIVERY|2016-03-08|2022-05-24|INE148O01028'
) -join "`n"
$investigationHash = Get-Sha256Text $canonicalEvidence

$qualityAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" -TimeoutSec 1800
$resolutionsAfter = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
if ($qualityAfter.totalCandles -ne $qualityBefore.totalCandles -or
    $qualityAfter.unresolvedFindingCount -ne $qualityBefore.unresolvedFindingCount -or
    $resolutionsAfter.Count -ne $resolutionsBefore.Count -or
    $latestAfter.jobId -ne $latestBefore.jobId -or
    $latestAfter.status -ne $latestBefore.status -or
    $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
    $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
    $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
    $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
    $latestAfter.workerEnabled) {
    throw 'A Batch 3 candle, finding, resolution, or job checkpoint changed during investigation.'
}

$report = [pscustomobject]@{
    investigatedAt = (Get-Date).ToUniversalTime().ToString('o')
    status = 'COMPLETED'
    jobId = $JobId
    batchNumber = $batchNumber
    reviewedManifestHash = $normalizedManifestHash
    reviewedPlanHash = $normalizedPlanHash
    investigationHash = $investigationHash
    openFindingCount = $openItems.Count
    sourceFailureFindingCount = 4
    historicalIdentityFindingCount = 5
    prelistingFindingCount = 1
    archiveRequestCount = $archiveSummaries.Count
    archiveEvidence = $archiveSummaries
    historicalOfficialRows = $officialRows
    recommendedChanges = $recommendedChanges
    candlesBefore = $qualityBefore.totalCandles
    candlesAfter = $qualityAfter.totalCandles
    resolutionsBefore = $resolutionsBefore.Count
    resolutionsAfter = $resolutionsAfter.Count
    workerEnabled = $latestAfter.workerEnabled
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-open-findings-investigation-$JobId.json"
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $outputPath -Encoding utf8

[pscustomobject]@{
    Status = $report.status
    JobId = $report.jobId
    BatchNumber = $report.batchNumber
    ReviewedPlanHash = $report.reviewedPlanHash
    InvestigationHash = $report.investigationHash
    OpenFindingCount = $report.openFindingCount
    ParserFindingCount = $report.sourceFailureFindingCount
    HistoricalIdentityFindingCount = $report.historicalIdentityFindingCount
    PrelistingFindingCount = $report.prelistingFindingCount
    ArchiveRequestCount = $report.archiveRequestCount
    CandlesBefore = $report.candlesBefore
    CandlesAfter = $report.candlesAfter
    ResolutionsBefore = $report.resolutionsBefore
    ResolutionsAfter = $report.resolutionsAfter
    WorkerEnabled = $report.workerEnabled
    FullInvestigationPath = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Historical identity evidence'
$officialRows |
    Format-Table CurrentSymbol, TradingDate, OfficialSymbol, OfficialIsin, PreviousClose, Close -AutoSize

Write-Host ''
Write-Host 'Correction decisions'
@(
    [pscustomobject]@{ Findings = 4; Cause = 'NSE dd-MMM-yy parser gap'; Correction = 'Parser support, then feature exclusions' }
    [pscustomobject]@{ Findings = 5; Cause = 'Historical exchange identities'; Correction = 'Three effective-dated identity aliases' }
    [pscustomobject]@{ Findings = 1; Cause = 'DELHIVERY pre-listing provider row'; Correction = 'One-session feature exclusion' }
) | Format-Table -AutoSize

Write-Host ''
Write-Host 'STEP 39 COMPLETE: all ten open Batch 3 findings have one evidence-backed correction path.'
Write-Host 'No candle, finding, exclusion, resolution, or backfill checkpoint was written.'
Write-Host 'Share this complete summary. The next reviewed step will implement these corrections and regenerate all 7036 recommendations.'
