[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [datetime]$AsOf,

    [Parameter(Mandatory = $true)]
    [string]$SourceName,

    [Parameter(Mandatory = $true)]
    [uri]$SourceUrl,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resolvedCsvPath = (Resolve-Path -LiteralPath $CsvPath).Path
$asOfText = $AsOf.ToString('yyyy-MM-dd')
$sourceHash = (Get-FileHash -LiteralPath $resolvedCsvPath -Algorithm SHA256).Hash.ToLowerInvariant()
$stem = "nifty500-historical-membership-preview-$asOfText-$sourceHash"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "$stem.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $payload = [System.IO.File]::ReadAllBytes($resolvedCsvPath)
    $encodedSourceName = [uri]::EscapeDataString($SourceName)
    $encodedSourceUrl = [uri]::EscapeDataString($SourceUrl.AbsoluteUri)
    $uri = "$BaseUrl/api/v1/training/nifty500-membership-preview" +
        "?asOf=$asOfText" +
        "&sourceName=$encodedSourceName" +
        "&sourceUrl=$encodedSourceUrl" +
        "&expectedSourceSha256=$sourceHash"

    Write-Host "Validating the authorized date-effective NIFTY 500 source for $asOfText..."
    Write-Host "Source SHA-256: $sourceHash"
    Write-Host 'This preview is database read-only and cannot train a model or persist membership.'
    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -ContentType 'text/csv; charset=utf-8' `
        -Body $payload `
        -TimeoutSec 1800

    $preview | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, membershipContractVersion, universeCode,
        asOf, sourceName, sourceUrl, sourceSha256, sourceRecordCount,
        earliestEffectiveFrom, latestClosedEffectiveTo, openEndedPeriodCount,
        activeMemberCount, matchedActiveMemberCount, unmatchedActiveMemberCount,
        ambiguousActiveMemberCount, duplicateActiveSymbolCount,
        duplicateActiveIsinCount, overlappingPeriodCount,
        historicalMembershipStatus, exactAsOfMemberCount,
        allActiveMembersMatched, effectiveDateSafe, persistenceReady,
        trainingEligible, manifestHash, databaseWritesPerformed,
        ollamaCallCount, signalsCreated, ordersCreated |
        Format-List

    Write-Host ''
    Write-Host 'Active-member matching'
    $preview.activeMembers |
        Group-Object matchStatus |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize

    $unresolved = @(
        $preview.activeMembers | Where-Object { $_.matchStatus -ne 'MATCHED' }
    )
    if ($unresolved.Count -gt 0) {
        Write-Host ''
        Write-Host 'Unresolved active members'
        $unresolved |
            Select-Object sourceSymbol, sourceIsin, companyName,
                effectiveFrom, effectiveTo, matchStatus, matchBasis |
            Format-Table -AutoSize
    }

    $invalidMembers = @(
        $preview.activeMembers | Where-Object {
            $_.matchStatus -ne 'MATCHED' -or
            $null -eq $_.instrumentId -or
            [string]::IsNullOrWhiteSpace([string]$_.currentSymbol) -or
            $_.matchBasis -notin @('CURRENT_ISIN', 'HISTORICAL_ISIN')
        }
    )
    if ($preview.status -ne 'REVIEW_REQUIRED' -or
        $preview.membershipContractVersion -ne 'NIFTY500_HISTORICAL_MEMBERSHIP_V1' -or
        $preview.universeCode -ne 'NIFTY_500' -or
        $preview.asOf -ne $asOfText -or
        $preview.sourceSha256 -ne $sourceHash -or
        $preview.sourceRecordCount -lt 500 -or
        $preview.activeMemberCount -ne 500 -or
        $preview.activeMembers.Count -ne 500 -or
        $preview.matchedActiveMemberCount -ne 500 -or
        $preview.unmatchedActiveMemberCount -ne 0 -or
        $preview.ambiguousActiveMemberCount -ne 0 -or
        $preview.duplicateActiveSymbolCount -ne 0 -or
        $preview.duplicateActiveIsinCount -ne 0 -or
        $preview.overlappingPeriodCount -ne 0 -or
        $preview.historicalMembershipStatus -ne 'DATE_EFFECTIVE_SOURCE_PREVIEW' -or
        -not $preview.exactAsOfMemberCount -or
        -not $preview.allActiveMembersMatched -or
        -not $preview.effectiveDateSafe -or
        -not $preview.persistenceReady -or
        $preview.trainingEligible -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 0 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        @($preview.failedCheckpoints).Count -ne 0 -or
        $invalidMembers.Count -ne 0) {
        throw 'The historical membership preview did not reach every reviewed Step 61 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 61 COMPLETE: the authorized date-effective membership source passed every read-only checkpoint.'
    Write-Host 'No membership, dataset, model, Ollama request, signal, order, candle, or other database row was written.'
    Write-Host 'Share this complete summary and JSON artifact before historical membership persistence is prepared.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
