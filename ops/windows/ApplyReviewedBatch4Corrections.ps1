[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewedBy,
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

$batchNumber = 4
$expectedJobId = [guid]'30d59236-017c-406c-bc31-ef4bb1d4ee47'
$expectedManifestHash = '9c11c15a4cf82a840cdbbd3e52cbc872b7916c405172ce5571ecab549568614c'
$expectedIncompletePlanHash = '7ed43e44f0cc92404411c36f0d50364e3975d7715fb9685db0d425b9bd50cc6a'
$expectedInstrumentCount = 190
$expectedTotalChunks = 2190
$expectedUpstoxCandles = 520018
$expectedRejectedRows = 29
$expectedFindings = 6685
$expectedOfficialFindings = 1408
$expectedPeerFindings = 5106
$expectedCoverageFindings = 50
$expectedLargeMoveFindings = 121
$expectedSourceRequests = 1999
$expectedSecondaryItems = 1278
$expectedFeatureExclusionItems = 5287
$expectedExistingLargeMoveActions = 113
$expectedCorrectedLargeMoveActions = 120
$expectedOpenCount = 7
$reviewer = $ReviewedBy.Trim()
$manifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$incompletePlanHash = $ReviewedPlanHash.Trim().ToLowerInvariant()

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

function ConvertTo-InvariantDecimal {
    param([Parameter(Mandatory)]$Value)
    return [decimal]::Parse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Number,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-CurrentResolutions {
    param(
        [Parameter(Mandatory)][string]$ApiBaseUrl,
        [Parameter(Mandatory)][guid]$BackfillJobId
    )

    $response = Invoke-RestMethod `
        "$ApiBaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$BackfillJobId" `
        -TimeoutSec 900
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
    $relativePath = "content/historical/EQUITIES/$year/$month/cm${stamp}bhav.csv.zip"
    $sourceUrls = @(
        "https://archives.nseindia.com/$relativePath"
        "https://nsearchives.nseindia.com/$relativePath"
    )
    $sourceUrl = $null
    $archiveBytes = $null
    $lastDownloadError = $null
    foreach ($candidateUrl in $sourceUrls) {
        foreach ($attempt in 1..2) {
            try {
                $archiveBytes = $Client.GetByteArrayAsync($candidateUrl).GetAwaiter().GetResult()
                $sourceUrl = $candidateUrl
                break
            } catch {
                $lastDownloadError = $_
                Start-Sleep -Milliseconds 400
            }
        }
        if ($null -ne $archiveBytes) {
            break
        }
    }
    if ($null -eq $archiveBytes) {
        throw "Both NSE archive hosts rejected $(Get-IsoDate $TradingDate): $($lastDownloadError.Exception.Message)"
    }
    if ($archiveBytes.Length -eq 0 -or $archiveBytes.Length -gt 20MB) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) was empty or exceeded the 20 MB safety limit."
    }

    $memory = [System.IO.MemoryStream]::new($archiveBytes)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $memory,
        [System.IO.Compression.ZipArchiveMode]::Read
    )
    try {
        $entries = @($archive.Entries | Where-Object {
            $_.Name.EndsWith('.csv', [System.StringComparison]::OrdinalIgnoreCase)
        })
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
    $dateColumn = if ($headerNames -contains 'TIMESTAMP') {
        'TIMESTAMP'
    } elseif ($headerNames -contains 'TradDt') {
        'TradDt'
    } else {
        $null
    }
    if ($null -eq $dateColumn -or -not ($headerNames -contains 'SYMBOL')) {
        throw "NSE archive for $(Get-IsoDate $TradingDate) has an unexpected CSV layout."
    }

    return [pscustomobject]@{
        TradingDate = Get-IsoDate $TradingDate
        SourceUrl = $sourceUrl
        ArchiveSha256 = Get-Sha256Bytes $archiveBytes
        CsvEntry = $csvEntryName
        RowCount = $rows.Count
        DateColumn = $dateColumn
        Rows = @($rows | Where-Object { $_.SERIES -in @('EQ', 'BE', 'BZ') })
    }
}

function Get-ReviewedOfficialRow {
    param(
        [Parameter(Mandatory)]$Archive,
        [Parameter(Mandatory)]$Expected
    )

    $matches = @($Archive.Rows | Where-Object {
        $_.SYMBOL -eq $Expected.AliasSymbol -and
        $_.ISIN -eq $Expected.AliasIsin -and
        $_.SERIES -eq 'EQ'
    })
    if ($matches.Count -ne 1) {
        throw "Expected one $($Expected.AliasSymbol)/$($Expected.AliasIsin) EQ row on $($Archive.TradingDate), found $($matches.Count)."
    }
    $row = $matches[0]
    foreach ($priceName in @('PREVCLOSE', 'OPEN', 'HIGH', 'LOW', 'CLOSE')) {
        $actual = ConvertTo-InvariantDecimal $row.$priceName
        $expectedValue = ConvertTo-InvariantDecimal $Expected.$priceName
        if ($actual -ne $expectedValue) {
            throw "Official $priceName changed for $($Expected.CurrentSymbol) on $($Archive.TradingDate): expected $expectedValue, found $actual."
        }
    }
    if ((ConvertTo-InvariantDecimal $row.TOTTRDQTY) -ne
        (ConvertTo-InvariantDecimal $Expected.TOTTRDQTY)) {
        throw "Official volume changed for $($Expected.CurrentSymbol) on $($Archive.TradingDate)."
    }

    return [pscustomobject]@{
        CurrentSymbol = $Expected.CurrentSymbol
        TradingDate = $Archive.TradingDate
        OfficialSymbol = $row.SYMBOL
        OfficialIsin = $row.ISIN
        Series = $row.SERIES
        PreviousClose = ConvertTo-InvariantDecimal $row.PREVCLOSE
        Open = ConvertTo-InvariantDecimal $row.OPEN
        High = ConvertTo-InvariantDecimal $row.HIGH
        Low = ConvertTo-InvariantDecimal $row.LOW
        Close = ConvertTo-InvariantDecimal $row.CLOSE
        Volume = ConvertTo-InvariantDecimal $row.TOTTRDQTY
        SourceUrl = $Archive.SourceUrl
        ArchiveSha256 = $Archive.ArchiveSha256
    }
}

if ([string]::IsNullOrWhiteSpace($reviewer)) {
    throw 'ReviewedBy must contain the name of the person approving all Batch 4 corrections.'
}
if ($JobId -ne $expectedJobId -or
    $manifestHash -ne $expectedManifestHash -or
    $incompletePlanHash -ne $expectedIncompletePlanHash) {
    throw 'The supplied job, manifest, or plan is not the reviewed incomplete Batch 4 checkpoint.'
}

$analysisPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-analysis-$JobId.json"
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-suzlon-recovery-$JobId.json"
$checkpointAuditPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-quality-checkpoints-$JobId.json"
$investigationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-open-findings-investigation-$JobId.json"
$correctedAnalysisPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-corrected-analysis-$JobId.json"
$checkpointPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-checkpoints-$JobId.json"
$resultPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-$JobId.json"
$logPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-$JobId.log"
$requiredPaths = @($analysisPath, $creationPath, $recoveryPath, $checkpointAuditPath)
if (@($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -ne 0) {
    throw 'One or more reviewed Batch 4 analysis or checkpoint artifacts are missing.'
}

$originalAnalysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$creation = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$recovery = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
$checkpointAudit = Get-Content -LiteralPath $checkpointAuditPath -Raw | ConvertFrom-Json
$originalItems = @($originalAnalysis.items | Where-Object { $null -ne $_ })
$openItems = @($originalItems | Where-Object { $null -eq $_.recommendedResolutionType })
$expectedOpenKeys = @(
    'LARGE_MOVE|NAVA|2014-05-21|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|NAVA|2020-06-18|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|SHRIRAMFIN|2020-03-23|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|UNITDSPR|2012-11-12|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|UNOMINDA|2013-11-28|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|UNOMINDA|2014-06-30|OFFICIAL_INSTRUMENT_NOT_FOUND'
    'LARGE_MOVE|UNOMINDA|2014-09-15|OFFICIAL_INSTRUMENT_NOT_FOUND'
) | Sort-Object
$actualOpenKeys = @($openItems | ForEach-Object {
    '{0}|{1}|{2}|{3}' -f $_.findingType, $_.symbol, (Get-IsoDate $_.findingDate), $_.analysisStatus
} | Sort-Object)
$openDifferences = @(Compare-Object -ReferenceObject $expectedOpenKeys -DifferenceObject $actualOpenKeys)
$originalCandidateCount = $originalAnalysis.secondaryBackfillCandidateCount +
    $originalAnalysis.featureExclusionCandidateCount +
    $originalAnalysis.providerAdjustmentCandidateCount +
    $originalAnalysis.verifiedMoveCandidateCount
$auditChangedMetrics = @(
    $checkpointAudit.databaseProviderChangedMetrics | Where-Object { $null -ne $_ }
)

if ([guid]$originalAnalysis.jobId -ne $JobId -or
    $originalAnalysis.planHash -ne $incompletePlanHash -or
    $originalAnalysis.unresolvedFindingCount -ne $expectedFindings -or
    $originalAnalysis.officialSessionFindingCount -ne $expectedOfficialFindings -or
    $originalAnalysis.peerSessionFindingCount -ne $expectedPeerFindings -or
    $originalAnalysis.coverageGapFindingCount -ne $expectedCoverageFindings -or
    $originalAnalysis.largeMoveFindingCount -ne $expectedLargeMoveFindings -or
    $originalAnalysis.sourceRequestCount -ne $expectedSourceRequests -or
    $originalAnalysis.secondaryBackfillCandidateCount -ne $expectedSecondaryItems -or
    $originalAnalysis.featureExclusionCandidateCount -ne $expectedFeatureExclusionItems -or
    $originalAnalysis.providerAdjustmentCandidateCount +
        $originalAnalysis.verifiedMoveCandidateCount -ne $expectedExistingLargeMoveActions -or
    $originalCandidateCount -ne ($expectedFindings - $expectedOpenCount) -or
    $originalAnalysis.keepOpenCount -ne $expectedOpenCount -or
    $originalAnalysis.sourceFailureCount -ne 0 -or
    $originalAnalysis.analysisComplete -or
    $originalItems.Count -ne $expectedFindings -or
    $openItems.Count -ne $expectedOpenCount -or
    $openDifferences.Count -ne 0 -or
    $originalAnalysis.candlesWritten -or
    $originalAnalysis.resolutionsWritten -or
    $creation.reviewedManifestHash -ne $manifestHash -or
    [guid]$creation.verifiedStatus.jobId -ne $JobId -or
    [guid]$recovery.status.jobId -ne $JobId -or
    $recovery.status.status -ne 'COMPLETED' -or
    $checkpointAudit.status -ne 'REVIEW_REQUIRED' -or
    $checkpointAudit.reviewedManifestHash -ne $manifestHash -or
    $auditChangedMetrics.Count -ne 0 -or
    $checkpointAudit.jobCheckpointChanged -or
    $checkpointAudit.databaseResolutionCount -ne 0 -or
    $checkpointAudit.providerResolutionCount -ne 0 -or
    $checkpointAudit.databaseWritesPerformed) {
    throw 'The saved artifacts do not contain the exact reviewed incomplete Batch 4 plan and its seven open findings.'
}

$archiveExpectations = @(
    [pscustomobject]@{ CurrentSymbol='NAVA'; AliasSymbol='NBVENTURES'; AliasIsin='INE725A01022'; Date='2014-05-21'; PREVCLOSE='183.6'; OPEN='186'; HIGH='220.3'; LOW='186'; CLOSE='220.3'; TOTTRDQTY='118918' }
    [pscustomobject]@{ CurrentSymbol='NAVA'; AliasSymbol='NBVENTURES'; AliasIsin='INE725A01022'; Date='2020-06-18'; PREVCLOSE='38.25'; OPEN='38.2'; HIGH='45.9'; LOW='38.2'; CLOSE='45.9'; TOTTRDQTY='1648864' }
    [pscustomobject]@{ CurrentSymbol='SHRIRAMFIN'; AliasSymbol='SRTRANSFIN'; AliasIsin='INE721A01013'; Date='2020-03-23'; PREVCLOSE='580.9'; OPEN='522.85'; HIGH='550'; LOW='440'; CLOSE='452.05'; TOTTRDQTY='2208926' }
    [pscustomobject]@{ CurrentSymbol='UNITDSPR'; AliasSymbol='MCDOWELL-N'; AliasIsin='INE854D01016'; Date='2012-11-12'; PREVCLOSE='1360.5'; OPEN='1399.95'; HIGH='1874.6'; LOW='1376'; CLOSE='1832.95'; TOTTRDQTY='25325946' }
    [pscustomobject]@{ CurrentSymbol='UNOMINDA'; AliasSymbol='MINDAIND'; AliasIsin='INE405E01015'; Date='2013-11-28'; PREVCLOSE='182.2'; OPEN='180'; HIGH='218.6'; LOW='180'; CLOSE='218.6'; TOTTRDQTY='9538' }
    [pscustomobject]@{ CurrentSymbol='UNOMINDA'; AliasSymbol='MINDAIND'; AliasIsin='INE405E01015'; Date='2014-06-30'; PREVCLOSE='288.8'; OPEN='298'; HIGH='346.55'; LOW='298'; CLOSE='346.55'; TOTTRDQTY='72950' }
    [pscustomobject]@{ CurrentSymbol='UNOMINDA'; AliasSymbol='MINDAIND'; AliasIsin='INE405E01015'; Date='2014-09-15'; PREVCLOSE='432.6'; OPEN='519.1'; HIGH='519.1'; LOW='505'; CLOSE='519.1'; TOTTRDQTY='93660' }
)

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Force | Out-Host
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
    if ([guid]$latestBefore.jobId -ne $JobId -or
        $latestBefore.jobType -ne 'EXPANSION' -or
        $latestBefore.batchNumber -ne $batchNumber -or
        $latestBefore.status -ne 'COMPLETED' -or
        $latestBefore.instruments -ne $expectedInstrumentCount -or
        $latestBefore.totalChunks -ne $expectedTotalChunks -or
        $latestBefore.completedChunks -ne $expectedTotalChunks -or
        $latestBefore.failedChunks -ne 0 -or
        $latestBefore.acceptedRows -ne $expectedUpstoxCandles -or
        $latestBefore.rejectedRows -ne $expectedRejectedRows -or
        $latestBefore.workerEnabled) {
        throw 'The live job is not the exact reviewed completed Batch 4 checkpoint.'
    }

    Write-Host 'Verifying the seven reviewed historical-identity rows in immutable NSE daily archives...'
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MarketBrain/0.1 evidence-verifier'
    )
    $client.DefaultRequestHeaders.Referrer = [uri]'https://www.nseindia.com/all-reports'
    try {
        $archives = @{}
        foreach ($date in @($archiveExpectations.Date | Sort-Object -Unique)) {
            $archives[$date] = Get-NseArchiveEvidence -Client $client -TradingDate ([datetime]$date)
        }
    } finally {
        $client.Dispose()
    }

    $officialRows = @($archiveExpectations | ForEach-Object {
        Get-ReviewedOfficialRow -Archive $archives[$_.Date] -Expected $_
    })
    $canonicalEvidence = @(
        "job=$JobId"
        "manifest=$manifestHash"
        "incompletePlan=$incompletePlanHash"
        $officialRows | ForEach-Object {
            "row=$($_.CurrentSymbol)|$($_.TradingDate)|$($_.OfficialSymbol)|$($_.OfficialIsin)|$($_.PreviousClose)|$($_.Close)|$($_.ArchiveSha256)"
        }
    ) -join "`n"
    $investigationHash = Get-Sha256Text $canonicalEvidence
    $investigation = [pscustomobject]@{
        investigatedAt = [DateTimeOffset]::Now
        status = 'COMPLETED'
        jobId = $JobId
        batchNumber = $batchNumber
        reviewedManifestHash = $manifestHash
        reviewedIncompletePlanHash = $incompletePlanHash
        investigationHash = $investigationHash
        openFindingCount = $expectedOpenCount
        archiveRequestCount = $archives.Count
        historicalOfficialRows = $officialRows
        databaseWritesPerformed = $false
    }
    $investigation | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $investigationPath -Encoding utf8

    Write-Host ''
    Write-Host 'Reviewed historical identity evidence'
    $officialRows |
        Format-Table CurrentSymbol, TradingDate, OfficialSymbol, OfficialIsin, PreviousClose, Close -AutoSize

    $analysis = $null
    $persistedPlan = $null
    if (Test-Path -LiteralPath $correctedAnalysisPath -PathType Leaf) {
        $savedAnalysis = Get-Content -LiteralPath $correctedAnalysisPath -Raw | ConvertFrom-Json
        if ([guid]$savedAnalysis.jobId -eq $JobId -and
            $savedAnalysis.planHash -match '^[0-9a-f]{64}$' -and
            $savedAnalysis.analysisComplete) {
            $analysis = $savedAnalysis
            try {
                $encodedSavedHash = [uri]::EscapeDataString($analysis.planHash)
                $persistedPlan = Invoke-RestMethod `
                    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedSavedHash" `
                    -TimeoutSec 900
            } catch {
                $statusCode = 0
                if ($null -ne $_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($statusCode -ne 404) {
                    throw
                }
            }
        }
    }

    $qualityBefore = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
        -TimeoutSec 1800
    $resolutionsBefore = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
    if ($null -eq $persistedPlan -and
        ($qualityBefore.totalCandles -ne $expectedUpstoxCandles -or
         $qualityBefore.unresolvedFindingCount -ne $expectedFindings -or
         $resolutionsBefore.Count -ne 0)) {
        throw 'The live database is not the exact reviewed pre-remediation Batch 4 checkpoint.'
    }

    if ($null -eq $analysis) {
        Write-Host ''
        Write-Host 'Regenerating all 6685 actions with the four reviewed historical identities...'
        $analysis = Invoke-RestMethod `
            "$BaseUrl/api/v1/market-data/backfills/remaining-data-analysis?jobId=$JobId" `
            -TimeoutSec 7200
    } elseif ($null -ne $persistedPlan) {
        Write-Host "Resuming durable plan $($analysis.planHash); completed items will not be repeated."
    } else {
        Write-Host "Reusing locally saved corrected plan $($analysis.planHash); the live database is unchanged."
    }

    $items = @($analysis.items | Where-Object { $null -ne $_ })
    $candidateCount = $analysis.secondaryBackfillCandidateCount +
        $analysis.featureExclusionCandidateCount +
        $analysis.providerAdjustmentCandidateCount +
        $analysis.verifiedMoveCandidateCount
    $formerlyOpenItems = @($items | Where-Object {
        $key = '{0}|{1}|{2}|OFFICIAL_INSTRUMENT_NOT_FOUND' -f `
            $_.findingType, $_.symbol, (Get-IsoDate $_.findingDate)
        $expectedOpenKeys -contains $key
    })
    $unresolvedFormerlyOpen = @($formerlyOpenItems | Where-Object {
        $null -eq $_.recommendedResolutionType
    })
    $invalidHistoricalMatches = @($formerlyOpenItems | Where-Object {
        $expectedIdentity = switch ($_.symbol) {
            'NAVA' { 'NBVENTURES' }
            'SHRIRAMFIN' { 'SRTRANSFIN' }
            'UNITDSPR' { 'MCDOWELL-N' }
            'UNOMINDA' { 'MINDAIND' }
        }
        $_.officialSymbol -ne $expectedIdentity -or
        $_.matchBasis -ne 'HISTORICAL_ISIN' -or
        $_.recommendedResolutionType -notin @('VERIFIED_EXCHANGE_MOVE', 'PROVIDER_ADJUSTMENT')
    })
    $correctedLargeMoveActions = $analysis.providerAdjustmentCandidateCount +
        $analysis.verifiedMoveCandidateCount
    $checkpointResults = @(
        [pscustomobject]@{ Checkpoint='JobId'; Expected=[string]$JobId; Actual=[string]$analysis.jobId; Passed=([guid]$analysis.jobId -eq $JobId) }
        [pscustomobject]@{ Checkpoint='AnalysisComplete'; Expected='True'; Actual=[string]$analysis.analysisComplete; Passed=[bool]$analysis.analysisComplete }
        [pscustomobject]@{ Checkpoint='PlanHash'; Expected='64 lowercase hexadecimal characters, different from incomplete plan'; Actual=[string]$analysis.planHash; Passed=($analysis.planHash -match '^[0-9a-f]{64}$' -and $analysis.planHash -ne $incompletePlanHash) }
        [pscustomobject]@{ Checkpoint='UnresolvedFindingCount'; Expected=[string]$expectedFindings; Actual=[string]$analysis.unresolvedFindingCount; Passed=($analysis.unresolvedFindingCount -eq $expectedFindings) }
        [pscustomobject]@{ Checkpoint='OfficialSessionFindingCount'; Expected=[string]$expectedOfficialFindings; Actual=[string]$analysis.officialSessionFindingCount; Passed=($analysis.officialSessionFindingCount -eq $expectedOfficialFindings) }
        [pscustomobject]@{ Checkpoint='PeerSessionFindingCount'; Expected=[string]$expectedPeerFindings; Actual=[string]$analysis.peerSessionFindingCount; Passed=($analysis.peerSessionFindingCount -eq $expectedPeerFindings) }
        [pscustomobject]@{ Checkpoint='CoverageGapFindingCount'; Expected=[string]$expectedCoverageFindings; Actual=[string]$analysis.coverageGapFindingCount; Passed=($analysis.coverageGapFindingCount -eq $expectedCoverageFindings) }
        [pscustomobject]@{ Checkpoint='LargeMoveFindingCount'; Expected=[string]$expectedLargeMoveFindings; Actual=[string]$analysis.largeMoveFindingCount; Passed=($analysis.largeMoveFindingCount -eq $expectedLargeMoveFindings) }
        [pscustomobject]@{ Checkpoint='SourceRequestCount'; Expected=[string]$expectedSourceRequests; Actual=[string]$analysis.sourceRequestCount; Passed=($analysis.sourceRequestCount -eq $expectedSourceRequests) }
        [pscustomobject]@{ Checkpoint='SecondaryBackfillCandidateCount'; Expected=[string]$expectedSecondaryItems; Actual=[string]$analysis.secondaryBackfillCandidateCount; Passed=($analysis.secondaryBackfillCandidateCount -eq $expectedSecondaryItems) }
        [pscustomobject]@{ Checkpoint='FeatureExclusionCandidateCount'; Expected=[string]$expectedFeatureExclusionItems; Actual=[string]$analysis.featureExclusionCandidateCount; Passed=($analysis.featureExclusionCandidateCount -eq $expectedFeatureExclusionItems) }
        [pscustomobject]@{ Checkpoint='LargeMoveActionCount'; Expected=[string]$expectedCorrectedLargeMoveActions; Actual=[string]$correctedLargeMoveActions; Passed=($correctedLargeMoveActions -eq $expectedCorrectedLargeMoveActions) }
        [pscustomobject]@{ Checkpoint='CandidateCount'; Expected=[string]$expectedFindings; Actual=[string]$candidateCount; Passed=($candidateCount -eq $expectedFindings) }
        [pscustomobject]@{ Checkpoint='KeepOpenCount'; Expected='0'; Actual=[string]$analysis.keepOpenCount; Passed=($analysis.keepOpenCount -eq 0) }
        [pscustomobject]@{ Checkpoint='SourceFailureCount'; Expected='0'; Actual=[string]$analysis.sourceFailureCount; Passed=($analysis.sourceFailureCount -eq 0) }
        [pscustomobject]@{ Checkpoint='AnalysisItemCount'; Expected=[string]$expectedFindings; Actual=[string]$items.Count; Passed=($items.Count -eq $expectedFindings) }
        [pscustomobject]@{ Checkpoint='FormerlyOpenItemCount'; Expected=[string]$expectedOpenCount; Actual=[string]$formerlyOpenItems.Count; Passed=($formerlyOpenItems.Count -eq $expectedOpenCount) }
        [pscustomobject]@{ Checkpoint='UnresolvedFormerlyOpenCount'; Expected='0'; Actual=[string]$unresolvedFormerlyOpen.Count; Passed=($unresolvedFormerlyOpen.Count -eq 0) }
        [pscustomobject]@{ Checkpoint='InvalidHistoricalMatchCount'; Expected='0'; Actual=[string]$invalidHistoricalMatches.Count; Passed=($invalidHistoricalMatches.Count -eq 0) }
        [pscustomobject]@{ Checkpoint='CandlesWritten'; Expected='False'; Actual=[string]$analysis.candlesWritten; Passed=(-not [bool]$analysis.candlesWritten) }
        [pscustomobject]@{ Checkpoint='ResolutionsWritten'; Expected='False'; Actual=[string]$analysis.resolutionsWritten; Passed=(-not [bool]$analysis.resolutionsWritten) }
    )
    $failedCheckpoints = @($checkpointResults | Where-Object { -not $_.Passed })

    $analysis | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $correctedAnalysisPath -Encoding utf8
    [pscustomobject]@{
        checkedAt = [DateTimeOffset]::Now
        status = if ($failedCheckpoints.Count -eq 0) { 'PASSED' } else { 'REVIEW_REQUIRED' }
        jobId = $JobId
        manifestHash = $manifestHash
        incompletePlanHash = $incompletePlanHash
        correctedPlanHash = $analysis.planHash
        investigationHash = $investigationHash
        failedCheckpointCount = $failedCheckpoints.Count
        checkpoints = $checkpointResults
        formerlyOpenItems = $formerlyOpenItems
        databaseWritesPerformed = $false
    } | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $checkpointPath -Encoding utf8

    if ($failedCheckpoints.Count -gt 0) {
        Write-Host ''
        Write-Host 'Corrected-plan checkpoint failures'
        $failedCheckpoints | Format-Table Checkpoint, Expected, Actual -AutoSize
        throw "The corrected Batch 4 plan failed $($failedCheckpoints.Count) checkpoint(s); no remediation was requested."
    }

    [pscustomobject]@{
        Status = 'CORRECTED_PLAN_VERIFIED'
        JobId = $analysis.jobId
        InvestigationHash = $investigationHash
        CorrectedPlanHash = $analysis.planHash
        TotalItems = $candidateCount
        SecondaryBackfillItems = $analysis.secondaryBackfillCandidateCount
        FeatureExclusionItems = $analysis.featureExclusionCandidateCount
        ProviderAdjustmentItems = $analysis.providerAdjustmentCandidateCount
        VerifiedMoveItems = $analysis.verifiedMoveCandidateCount
        KeepOpenCount = $analysis.keepOpenCount
        SourceFailureCount = $analysis.sourceFailureCount
        FullInvestigationPath = $investigationPath
        FullCorrectedAnalysisPath = $correctedAnalysisPath
        FullCheckpointPath = $checkpointPath
    } | Format-List

    Write-Host ''
    Write-Host 'The seven previously open findings now have governed actions'
    $formerlyOpenItems |
        Sort-Object symbol, findingDate |
        Format-Table symbol, findingDate, analysisStatus, recommendedResolutionType, `
            officialSymbol, matchBasis -AutoSize

    Write-Host ''
    Write-Host 'Every corrected-plan invariant passed. Applying all 6685 reviewed actions now...'
    $request = @{
        jobId = $JobId
        expectedPlanHash = $analysis.planHash
        reviewedBy = $reviewer
    } | ConvertTo-Json

    $result = $null
    try {
        $result = Invoke-RestMethod `
            -Method Post `
            -Uri "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/apply" `
            -ContentType 'application/json' `
            -Body $request `
            -TimeoutSec 7200
    } catch {
        Write-Warning 'The application response was interrupted. Checking the durable checkpoint before failing.'
        try {
            $encodedHash = [uri]::EscapeDataString($analysis.planHash)
            $result = Invoke-RestMethod `
                "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
                -TimeoutSec 900
        } catch {
            throw 'The remediation response and durable checkpoint are unavailable. Do not alter data; rerun this exact command after connectivity returns.'
        }
    }

    $result | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $result |
        Select-Object status, jobId, planHash, totalItems, pendingItems, completedItems, failedItems,
            secondaryBackfillItems, featureExclusionItems, providerAdjustmentItems,
            secondaryCandlesReady, upstoxDailyCandleCount, secondaryDailyCandleCount,
            allSourceDailyCandleCount, planResolutionsWritten, currentResolutionCount,
            unresolvedFindingCount, workerEnabled, finalProviderSpotCheckRequired |
        Format-List

    $failures = @($result.failures | Where-Object { $null -ne $_ })
    if ($failures.Count -gt 0) {
        Write-Host ''
        Write-Host 'Failed remediation items'
        $failures | Format-Table symbol, findingType, findingDate, errorCode, detail -Wrap
    }

    $expectedAllSourceCandles = $expectedUpstoxCandles + $expectedSecondaryItems
    if ([guid]$result.jobId -ne $JobId -or
        $result.planHash -ne $analysis.planHash -or
        $result.status -ne 'COMPLETED' -or
        $result.totalItems -ne $expectedFindings -or
        $result.pendingItems -ne 0 -or
        $result.completedItems -ne $expectedFindings -or
        $result.failedItems -ne 0 -or
        $result.secondaryBackfillItems -ne $expectedSecondaryItems -or
        $result.featureExclusionItems -ne $expectedFeatureExclusionItems -or
        $result.providerAdjustmentItems -ne $analysis.providerAdjustmentCandidateCount -or
        $result.secondaryCandlesReady -ne $expectedSecondaryItems -or
        $result.upstoxDailyCandleCount -ne $expectedUpstoxCandles -or
        $result.secondaryDailyCandleCount -ne $expectedSecondaryItems -or
        $result.allSourceDailyCandleCount -ne $expectedAllSourceCandles -or
        $result.planResolutionsWritten -ne $expectedFindings -or
        $result.currentResolutionCount -ne $expectedFindings -or
        $result.unresolvedFindingCount -ne 0 -or
        $result.workerEnabled -or
        -not $result.finalProviderSpotCheckRequired) {
        throw 'The Batch 4 remediation returned, but one or more reviewed final invariants differ.'
    }

    $latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
    if ([guid]$latestAfter.jobId -ne $JobId -or
        $latestAfter.status -ne 'COMPLETED' -or
        $latestAfter.completedChunks -ne $expectedTotalChunks -or
        $latestAfter.failedChunks -ne 0 -or
        $latestAfter.acceptedRows -ne $expectedUpstoxCandles -or
        $latestAfter.rejectedRows -ne $expectedRejectedRows -or
        $latestAfter.workerEnabled) {
        throw 'The immutable Batch 4 job checkpoint changed during remediation.'
    }

    Write-Host ''
    Write-Host 'BATCH 4 REMEDIATION COMPLETE: all 6685 reviewed corrections are durable and every checkpoint passed.'
    Write-Host "The original $expectedUpstoxCandles Upstox candles and all $expectedRejectedRows rejected provider rows were preserved."
    Write-Host "$expectedSecondaryItems official NSE candles were added under the separate governed source."
    Write-Host "$($analysis.featureExclusionCandidateCount) feature exclusions, $($analysis.providerAdjustmentCandidateCount) provider adjustments, and $($analysis.verifiedMoveCandidateCount) verified moves were recorded."
    Write-Host "The complete result was saved to $resultPath."
    Write-Host 'A final read-only provider quality audit is still required before model-training or backtesting eligibility.'
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Host
    }
}
