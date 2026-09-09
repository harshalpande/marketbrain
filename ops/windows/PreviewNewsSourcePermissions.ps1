[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$RequestedOn,

    [Parameter()]
    [string]$PreparedBy = 'Harshal Pande',

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$requestedOnText = $RequestedOn.ToString('yyyy-MM-dd')
$stem = "news-source-permission-preview-$requestedOnText"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "$stem.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

function New-PendingSource {
    param(
        [string]$SourceKey,
        [string]$DisplayName,
        [string]$SourceType,
        [string]$SourceUrl,
        [string]$EvidenceReference = 'EMAIL_REQUEST_SENT'
    )

    return [ordered]@{
        sourceKey                    = $SourceKey
        displayName                  = $DisplayName
        sourceType                   = $SourceType
        permissionStatus             = 'AWAITING_RESPONSE'
        sourceUrl                    = $SourceUrl
        permissionEvidenceReference  = $EvidenceReference
        requestedOn                  = $requestedOnText
        decidedOn                    = $null
        retentionDays                = $null
        headlineStorageAllowed       = $false
        snippetStorageAllowed        = $false
        fullTextStorageAllowed       = $false
        localAiProcessingAllowed     = $false
        derivedDataRetentionAllowed  = $false
        attributionRequired          = $false
        permittedFields              = @()
    }
}

function New-TermsReviewSource {
    param(
        [string]$SourceKey,
        [string]$DisplayName,
        [string]$SourceUrl
    )

    return [ordered]@{
        sourceKey                    = $SourceKey
        displayName                  = $DisplayName
        sourceType                   = 'OFFICIAL_DISCLOSURE'
        permissionStatus             = 'TERMS_REVIEW_REQUIRED'
        sourceUrl                    = $SourceUrl
        permissionEvidenceReference  = 'PUBLISHED_TERMS_PENDING_REVIEW'
        requestedOn                  = $null
        decidedOn                    = $null
        retentionDays                = $null
        headlineStorageAllowed       = $false
        snippetStorageAllowed        = $false
        fullTextStorageAllowed       = $false
        localAiProcessingAllowed     = $false
        derivedDataRetentionAllowed  = $false
        attributionRequired          = $false
        permittedFields              = @()
    }
}

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $sources = @(
        New-PendingSource -SourceKey 'MARKETAUX_API' -DisplayName 'Marketaux API' `
            -SourceType 'NEWS_API' -SourceUrl 'https://www.marketaux.com/tos'
        New-PendingSource -SourceKey 'ECONOMIC_TIMES_RSS' -DisplayName 'Economic Times RSS' `
            -SourceType 'RSS' -SourceUrl 'https://economictimes.indiatimes.com/rss.cms' `
            -EvidenceReference 'EMAIL_AND_X_REQUEST_SENT'
        New-PendingSource -SourceKey 'LIVEMINT_RSS' -DisplayName 'Mint RSS' `
            -SourceType 'RSS' -SourceUrl 'https://www.livemint.com/rss'
        New-PendingSource -SourceKey 'BUSINESS_STANDARD_RSS' -DisplayName 'Business Standard RSS' `
            -SourceType 'RSS' -SourceUrl 'https://www.business-standard.com/rss-feeds/listing'
        New-TermsReviewSource -SourceKey 'NSE_DISCLOSURES' `
            -DisplayName 'NSE corporate disclosures' `
            -SourceUrl 'https://www.nseindia.com/companies-listing/corporate-filings-announcements'
        New-TermsReviewSource -SourceKey 'BSE_DISCLOSURES' `
            -DisplayName 'BSE corporate announcements' `
            -SourceUrl 'https://www.bseindia.com/corporates/ann.html'
        New-TermsReviewSource -SourceKey 'SEBI_PUBLIC_UPDATES' `
            -DisplayName 'SEBI public updates' `
            -SourceUrl 'https://www.sebi.gov.in/'
        New-TermsReviewSource -SourceKey 'RBI_PRESS_RELEASES' `
            -DisplayName 'RBI press releases' `
            -SourceUrl 'https://www.rbi.org.in/Scripts/BS_PressReleaseDisplay.aspx'
    )

    $request = [ordered]@{
        preparedOn = $requestedOnText
        preparedBy = $PreparedBy
        sources    = $sources
    }
    $body = $request | ConvertTo-Json -Depth 10

    Write-Host 'Previewing the governed news-source permission register...'
    Write-Host 'No news source will be contacted and no integration can be enabled by this request.'
    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/news/source-permissions/preview" `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 300

    $preview | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, permissionContractVersion, preparedOn,
        preparedBy, sourceCount, awaitingResponseCount,
        termsReviewRequiredCount, approvedCount, rejectedCount,
        permissionCompleteCount, integrationEligibleCount,
        integrationEnabledCount, registerPersistenceReady,
        contentIngestionAllowed, manifestHash, databaseWritesPerformed,
        providerRequestCount, articlesStored, ollamaCallCount,
        newsFeaturesCreated, signalsCreated, ordersCreated |
        Format-List

    Write-Host ''
    Write-Host 'Permission-gated sources'
    $preview.sources |
        Select-Object sourceKey, sourceType, permissionStatus,
            integrationEligible, integrationEnabled |
        Format-Table -AutoSize

    $unsafe = @(
        $preview.sources | Where-Object {
            $_.integrationEnabled -or
            ($_.permissionStatus -ne 'APPROVED' -and (
                $_.headlineStorageAllowed -or
                $_.snippetStorageAllowed -or
                $_.fullTextStorageAllowed -or
                $_.localAiProcessingAllowed -or
                $_.derivedDataRetentionAllowed
            ))
        }
    )
    if ($preview.status -ne 'REVIEW_REQUIRED' -or
        $preview.permissionContractVersion -ne 'NEWS_SOURCE_PERMISSION_V1' -or
        $preview.preparedOn -ne $requestedOnText -or
        $preview.sourceCount -ne 8 -or
        $preview.sources.Count -ne 8 -or
        $preview.awaitingResponseCount -ne 4 -or
        $preview.termsReviewRequiredCount -ne 4 -or
        $preview.approvedCount -ne 0 -or
        $preview.rejectedCount -ne 0 -or
        $preview.permissionCompleteCount -ne 0 -or
        $preview.integrationEligibleCount -ne 0 -or
        $preview.integrationEnabledCount -ne 0 -or
        -not $preview.registerPersistenceReady -or
        $preview.contentIngestionAllowed -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
        $preview.databaseWritesPerformed -or
        $preview.providerRequestCount -ne 0 -or
        $preview.articlesStored -ne 0 -or
        $preview.ollamaCallCount -ne 0 -or
        $preview.newsFeaturesCreated -ne 0 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        $preview.failedCheckpoints.Count -ne 0 -or
        $unsafe.Count -ne 0) {
        throw 'The news-source permission preview did not reach every reviewed Step 62 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 62 COMPLETE: the permission register contract is deterministic and all eight sources are disabled.'
    Write-Host 'No provider request, article, database row, Ollama call, feature, signal, or order was created.'
    Write-Host 'Share this summary and JSON artifact before permission-register persistence is prepared.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
