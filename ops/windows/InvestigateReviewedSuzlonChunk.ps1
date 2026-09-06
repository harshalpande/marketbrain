[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$JobId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$EnvFile = '.env',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$batchNumber = 4
$expectedInstrumentCount = 190
$expectedTotalChunks = 2190
$expectedCompletedChunks = 2189
$expectedFailedChunks = 1
$expectedAcceptedRows = 519772
$expectedRejectedRows = 29
$reviewedSymbol = 'SUZLON'
$reviewedInstrumentKey = 'NSE_EQ|INE040H01021'
$reviewedFrom = [datetime]'2015-09-02'
$reviewedTo = [datetime]'2016-09-01'
$reviewedTradingDate = '2015-12-31'
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$providerUrl = 'https://api.upstox.com/v3/historical-candle/' +
    [uri]::EscapeDataString($reviewedInstrumentKey) +
    '/days/1/2016-09-01/2015-09-02'
$officialUrl = 'https://archives.nseindia.com/content/historical/EQUITIES/2015/DEC/cm31DEC2015bhav.csv.zip'

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory "expansion-batch-4-suzlon-investigation-$JobId.log"
$resultPath = Join-Path $OutputDirectory "expansion-batch-4-suzlon-investigation-$JobId.json"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Host
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health"
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
    $status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
    if ([guid]$latest.jobId -ne $JobId -or
        [guid]$status.jobId -ne $JobId -or
        $status.jobType -ne 'EXPANSION' -or
        $status.batchNumber -ne $batchNumber -or
        $status.instruments -ne $expectedInstrumentCount -or
        $status.totalChunks -ne $expectedTotalChunks -or
        $status.status -ne 'PARTIAL_FAILED' -or
        $status.completedChunks -ne $expectedCompletedChunks -or
        $status.failedChunks -ne $expectedFailedChunks -or
        $status.acceptedRows -ne $expectedAcceptedRows -or
        $status.rejectedRows -ne $expectedRejectedRows) {
        throw 'The live job is not the exact reviewed Batch 4 partial-failure checkpoint.'
    }
    if ($status.workerEnabled) {
        throw 'The backfill worker must be disabled during the SUZLON evidence review.'
    }

    $instrumentPayload = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
    $instruments = @($instrumentPayload | ForEach-Object { $_ })
    $failedInstruments = @($instruments | Where-Object { $_.failedChunks -gt 0 })
    $suzlon = @($instruments | Where-Object { $_.symbol -eq $reviewedSymbol })
    if ($instruments.Count -ne $expectedInstrumentCount -or
        $failedInstruments.Count -ne 1 -or
        $failedInstruments[0].symbol -ne $reviewedSymbol -or
        $suzlon.Count -ne 1 -or
        $suzlon[0].totalChunks -ne 15 -or
        $suzlon[0].completedChunks -ne 14 -or
        $suzlon[0].failedChunks -ne 1) {
        throw 'The failed-instrument inventory is not the single reviewed SUZLON failure.'
    }

    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
        throw "The local environment file was not found at $EnvFile."
    }
    $tokenLine = Get-Content -LiteralPath $EnvFile |
        Where-Object { $_ -match '^\s*MARKETBRAIN_UPSTOX_ANALYTICS_TOKEN=' } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($tokenLine)) {
        throw 'MARKETBRAIN_UPSTOX_ANALYTICS_TOKEN is missing from the local environment file.'
    }
    $analyticsToken = ($tokenLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($analyticsToken)) {
        throw 'MARKETBRAIN_UPSTOX_ANALYTICS_TOKEN is empty in the local environment file.'
    }

    Write-Host 'Downloading the reviewed SUZLON provider range without printing the Analytics Token...'
    $headers = @{
        Authorization = "Bearer $analyticsToken"
        Accept = 'application/json'
    }
    $rawProviderResponse = Invoke-WebRequest -Method Get -Uri $providerUrl -Headers $headers
    $providerPayload = $rawProviderResponse.Content | ConvertFrom-Json
    $indiaOffset = [TimeSpan]::FromMinutes(330)
    $providerRows = @(
        $providerPayload.data.candles | ForEach-Object {
            $opened = [DateTimeOffset]::Parse([string]$_[0])
            [pscustomobject]@{
                tradingDate = $opened.ToOffset($indiaOffset).ToString('yyyy-MM-dd')
                openedAt = [string]$_[0]
                open = $_[1]
                high = $_[2]
                low = $_[3]
                close = $_[4]
                volume = $_[5]
            }
        }
    )
    $duplicateGroups = @(
        $providerRows | Group-Object tradingDate | Where-Object { $_.Count -gt 1 }
    )
    $targetRows = @(
        $providerRows | Where-Object { $_.tradingDate -eq $reviewedTradingDate }
    )

    Add-Type -AssemblyName System.Net.Http
    Add-Type -AssemblyName System.IO.Compression
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
        $client.DefaultRequestHeaders.Referrer = [uri]'https://www.nseindia.com/'
        $officialBytes = $client.GetByteArrayAsync($officialUrl).GetAwaiter().GetResult()
    } finally {
        $client.Dispose()
    }
    $officialArchiveHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($officialBytes)
    ).ToLowerInvariant()
    $memory = [System.IO.MemoryStream]::new($officialBytes)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $memory,
            [System.IO.Compression.ZipArchiveMode]::Read
        )
        try {
            $entry = $archive.Entries |
                Where-Object { $_.Name -like '*.csv' } |
                Select-Object -First 1
            if ($null -eq $entry) {
                throw 'The official NSE archive contains no CSV entry.'
            }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                $officialRows = @(
                    $reader.ReadToEnd() | ConvertFrom-Csv |
                        Where-Object { $_.SYMBOL -eq $reviewedSymbol -and $_.SERIES -eq 'EQ' }
                )
            } finally {
                $reader.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $memory.Dispose()
    }

    if ($duplicateGroups.Count -ne 1 -or
        $targetRows.Count -ne 2 -or
        $officialRows.Count -ne 1 -or
        $officialRows[0].ISIN -ne 'INE040H01021') {
        throw 'The live provider or official evidence shape differs from the reviewed SUZLON failure.'
    }

    $providerResponseHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($rawProviderResponse.Content)
        )
    ).ToLowerInvariant()
    $result = [pscustomobject]@{
        investigatedAt = (Get-Date).ToUniversalTime().ToString('o')
        status = 'EVIDENCE_CAPTURED'
        jobId = $JobId
        batchNumber = $batchNumber
        reviewedManifestHash = $normalizedHash
        symbol = $reviewedSymbol
        providerInstrumentKey = $reviewedInstrumentKey
        fromDate = $reviewedFrom.ToString('yyyy-MM-dd')
        toDate = $reviewedTo.ToString('yyyy-MM-dd')
        providerUrl = $providerUrl
        providerResponseHash = $providerResponseHash
        providerRowCount = $providerRows.Count
        duplicateTradingDateCount = $duplicateGroups.Count
        targetRows = $targetRows
        officialBhavcopyUrl = $officialUrl
        officialArchiveHash = $officialArchiveHash
        officialRows = $officialRows
        databaseWritesPerformed = $false
        workerEnabled = $status.workerEnabled
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8

    [pscustomobject]@{
        Status = $result.status
        JobId = $JobId
        BatchNumber = $batchNumber
        ManifestHash = $normalizedHash
        Symbol = $reviewedSymbol
        ProviderRows = $providerRows.Count
        DuplicateTradingDates = $duplicateGroups.Count
        TargetRowCount = $targetRows.Count
        OfficialRowCount = $officialRows.Count
        DatabaseWritesPerformed = $false
        WorkerEnabled = $status.workerEnabled
        FullEvidencePath = $resultPath
        FullLogPath = $logPath
    } | Format-List

    Write-Host ''
    Write-Host 'Provider rows for the conflicting trading date'
    $targetRows | Format-Table tradingDate, openedAt, open, high, low, close, volume -AutoSize

    Write-Host ''
    Write-Host 'Official NSE Bhavcopy row'
    $officialRows |
        Select-Object SYMBOL, SERIES, OPEN, HIGH, LOW, CLOSE, TOTTRDQTY, TIMESTAMP, ISIN |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'SUZLON EVIDENCE CAPTURE COMPLETE: no job, chunk, candle, finding, or resolution was changed.'
    Write-Host 'Share the complete summary, both evidence tables, and the JSON artifact before retrying Batch 4.'
} finally {
    Remove-Variable analyticsToken, tokenLine, headers, rawProviderResponse, providerPayload `
        -ErrorAction SilentlyContinue
    if ($transcriptStarted) {
        Stop-Transcript | Out-Host
    }
}
