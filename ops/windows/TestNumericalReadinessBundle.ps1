#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')
$script:checks=0
function Assert-Bundle([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
function Copy-Bundle($Value){$Value | ConvertTo-Json -Depth 16 | ConvertFrom-Json}
function Must-Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{[void](& $Action)}catch{$failed=$true};Assert-Bundle $failed $Message}
$calendar=Get-Content (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json') -Raw | ConvertFrom-Json
$sessions=@(Get-NumericalCalendarSessions $calendar)
function New-BundleFixture {
    $bars=@(for($i=0;$i -lt $sessions.Count;$i++){[pscustomobject]@{candleId=$i+1;date=$sessions[$i];source='UPSTOX';receivedAt='2026-09-01T00:00:00Z';excluded=$false;open=100;high=120;low=80;close=110;volume=1000}})
    $dates=@('2026-04-10','2026-05-08','2026-06-05')
    $rows=@(foreach($date in $dates){
        $window=@($bars | Where-Object {$_.date -le $date} | Select-Object -Last 252)
        [pscustomobject]@{decisionDate=$date;status='FEATURES_ONLY_CALENDAR_UNVERIFIED';featureFrom=$window[0].date;observationCount=252;sourceCandleIds=@($window.candleId);features=[pscustomobject]@{previousClose=100;dailyReturnPercent=10;sma20=100;sma50=100;sma200=100;ema12=100;ema26=100;rsi14=50;atr14=10;annualizedVolatility20Percent=10;volumeRatio20=1;rangePosition252Percent=50}}
    })
    [pscustomobject]@{
        version='NUMERICAL_FEATURE_EVIDENCE_V1';status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917'
        snapshot=[pscustomobject]@{
            status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';payloadSha256=('a'*64);partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0
            payload=[pscustomobject]@{version='OBSERVED_252_FEATURE_SNAPSHOT_V1';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917';datasetManifestHash=('b'*64);asOf='2026-06-05';windowFrom='2024-06-06';offset=0;limit=1;decisionDates=$dates;instruments=@([pscustomobject]@{instrumentId=1;symbol='FIXTURE';rawRowCount=$bars.Count;truncated=$false;canonicalBars=$bars;rows=$rows})}
        }
    }
}
function New-PriceFixture {
    [pscustomobject]@{version='NUMERICAL_PRICE_COLLECTION_V1';status='PRICE_POLICY_REVIEW_REQUIRED';inputSha256=('c'*64);result=[pscustomobject]@{
        version='NUMERICAL_PRICE_EVIDENCE_V1';status='PRICE_POLICY_REVIEW_REQUIRED';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917';datasetManifestHash=('b'*64);fromDate='2025-04-03';throughDate='2026-06-05';offset=0;limit=1;partial=$false
        trainingAuthorized=$false;databaseWritesPerformed=$false;providerCallCount=0;modelCallCount=0;ordersCreated=0
        instruments=@([pscustomobject]@{instrumentId=1;symbol='FIXTURE';partial=$false;corporateActions=@();remainingGates=@('CORPORATE_ACTION_COVERAGE_UNKNOWN','NO_VERIFIED_ADJUSTMENT_FACTORS_OR_EXECUTABLE_PRICE_BINDING')})
    }}
}
$f=New-BundleFixture;$p=New-PriceFixture
$r=Get-NumericalReadinessBundle $f $p ('c'*64) $calendar
Assert-Bundle ($r.summary.featureInputPassedCount -eq 3) 'Valid allowlist blocked.'
Assert-Bundle ($r.summary.arithmeticOnlyCount -eq 1 -and $r.summary.unavailableHorizonCount -eq 2) 'Horizon coverage fabricated.'
Assert-Bundle ($r.rows[0].labelPreflight.entryDate -eq '2026-04-13' -and $r.rows[0].labelPreflight.exitDate -eq '2026-05-12') 'Off-by-one exchange-session label.'
Assert-Bundle ($r.summary.purgedCount -eq 1 -and $r.summary.unknownLabelEndCount -eq 2) 'Split overlap ignored.'
Assert-Bundle ($r.rows[0].receivedAfterCutoffCount -eq 252 -and $r.rows[0].asKnownReplayStatus -eq 'NOT_ESTABLISHED') 'Backfill not disclosed.'
Assert-Bundle ($r.summary.certifiedLabelCount -eq 0 -and -not $r.trainingAuthorized -and $r.status -eq 'BLOCKED_FOR_TRAINING') 'Unverified prices promoted.'
$partial=New-PriceFixture;$partial.status='PARTIAL_PRICE_POLICY_REVIEW_REQUIRED';$partial.result.partial=$true;$partial.result.instruments[0].partial=$true
$r=Get-NumericalReadinessBundle (New-BundleFixture) $partial ('c'*64) $calendar
Assert-Bundle ($r.priceEvidencePartial -and $r.priceReview[0].partial -and -not $r.trainingAuthorized) 'Partial evidence concealed.'
$partial.status='PRICE_POLICY_REVIEW_REQUIRED'
Must-Reject {Get-NumericalReadinessBundle (New-BundleFixture) $partial ('c'*64) $calendar} 'Contradictory partial flag accepted.'
foreach($case in @('hash','manifest','from','symbol','training','provider','partial')){
    $p=New-PriceFixture
    switch($case){hash{$p.inputSha256='BAD'}manifest{$p.result.datasetManifestHash=('e'*64)}from{$p.result.fromDate='2025-05-01'}symbol{$p.result.instruments[0].symbol='OTHER'}training{$p.result.trainingAuthorized=$true}provider{$p.result.providerCallCount=1}partial{$p.result.partial='false'}}
    Must-Reject {Get-NumericalReadinessBundle (New-BundleFixture) $p ('c'*64) $calendar} "Unsafe price input accepted: $case"
}
foreach($case in @('futureFeature','stringFeature','missingFeature','futureSource')){
    $f=New-BundleFixture
    switch($case){
        futureFeature{$f.snapshot.payload.instruments[0].rows[0].features | Add-Member actualRank 1}
        stringFeature{$f.snapshot.payload.instruments[0].rows[0].features.rsi14='50'}
        missingFeature{$f.snapshot.payload.instruments[0].rows[0].features.PSObject.Properties.Remove('sma200')}
        futureSource{$f.snapshot.payload.instruments[0].rows[0].sourceCandleIds[-1]=$f.snapshot.payload.instruments[0].canonicalBars[-1].candleId}
    }
    $r=Get-NumericalReadinessBundle $f (New-PriceFixture) ('c'*64) $calendar
    Assert-Bundle ($r.rows[0].featureInputStatus -eq 'BLOCKED') "Leaking/invalid feature accepted: $case"
}
$unknown=New-BundleFixture;$unknown.snapshot.payload.instruments[0].canonicalBars[-1].receivedAt=$null
$r=Get-NumericalReadinessBundle $unknown (New-PriceFixture) ('c'*64) $calendar
Assert-Bundle ($r.rows[2].unknownReceivedAtCount -eq 1 -and $r.rows[2].asKnownReplayStatus -eq 'NOT_ESTABLISHED') 'Unknown availability passed.'
$f=New-BundleFixture;$bars=$f.snapshot.payload.instruments[0].canonicalBars
foreach($case in @('missing','excluded','negative','outsideOhlc','null','bool')){
    $b=Copy-Bundle $bars;$day='2026-04-20';$bar=$b | Where-Object date -eq $day
    switch($case){missing{$b=@($b | Where-Object date -ne $day)}excluded{$bar.excluded=$true}negative{$bar.open=-1}outsideOhlc{$bar.low=115}null{$bar.close=$null}bool{$bar.open=$true}}
    $r=Get-NumericalLabelPreflight '2026-04-10' $sessions $b
    Assert-Bundle ($null -eq $r.indicativeGrossPercent -and $r.problemDate -eq $day -and $r.entryDate -eq '2026-04-13') "Bad bar skipped/accepted: $case"
}
$vectors=Get-Content (Join-Path $PSScriptRoot '..\..\marketbrain-service\src\test\resources\numerical-label-parity.json') -Raw | ConvertFrom-Json
foreach($v in $vectors.cases){
    $b=Copy-Bundle $bars
    $entry=$b | Where-Object date -eq '2026-04-13';$exit=$b | Where-Object date -eq '2026-05-12'
    foreach($name in @('open','high','low','close')){$entry.$name=$v.entry;$exit.$name=$v.exit}
    $r=Get-NumericalLabelPreflight '2026-04-10' $sessions $b
    $scenario=$r.costSensitivity | Where-Object assumedRoundTripCostBps -eq $v.costBps
    Assert-Bundle ($r.indicativeGrossPercent -eq [decimal]$v.gross -and $scenario.indicativeNetPercent -eq [decimal]$v.net) 'Shared Java/PowerShell decimal parity failed.'
}
$splitRows=@([pscustomobject]@{instrumentId=1;decisionDate='2026-01-01';exitDate='2026-02-01'},[pscustomobject]@{instrumentId=2;decisionDate='2026-01-01';exitDate='2026-01-31'},[pscustomobject]@{instrumentId=1;decisionDate='2026-02-01';exitDate='2026-03-01'})
$split=Get-NumericalSplitPreflight $splitRows '2026-02-01' '2026-03-01'
Assert-Bundle ($split.purgedCount -eq 2 -and $split.assignments[1].status -eq 'RETAINED_FOR_DIAGNOSTIC_ONLY') 'Boundary equality not purged.'
Assert-Bundle ($split.assignments[0].partition -eq $split.assignments[1].partition) 'Same-date stocks split across folds.'
Must-Reject {Get-NumericalSplitPreflight @($splitRows[0],$splitRows[0]) '2026-02-01' '2026-03-01'} 'Duplicate split row accepted.'
Must-Reject {Get-NumericalSplitPreflight $splitRows '2026-03-01' '2026-02-01'} 'Reversed split accepted.'
function Invoke-RestMethod {throw 'Network forbidden.'}
function Invoke-WebRequest {throw 'Network forbidden.'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-bundle-tests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
$fp=Join-Path $temp 'feature.json';$pp=Join-Path $temp 'price.json'
[IO.File]::WriteAllText($fp,((New-BundleFixture) | ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $fp).Hash;$p=New-PriceFixture;$p.inputSha256=$hash
[IO.File]::WriteAllText($pp,($p | ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
for($i=0;$i -lt 2;$i++){& (Join-Path $PSScriptRoot 'ReviewNumericalReadinessBundle.ps1') -FeatureEvidencePath $fp -PriceEvidencePath $pp -OutputDirectory $temp | Out-Null}
$reports=@(Get-ChildItem -LiteralPath $temp -Filter 'numerical-readiness-bundle-*.json')
Assert-Bundle ($reports.Count -eq 2) 'Repeated runs overwrote reports.'
foreach($file in $reports){$saved=Get-Content $file.FullName -Raw | ConvertFrom-Json;Assert-Bundle ($saved.status -eq 'BLOCKED_FOR_TRAINING' -and $saved.result.summary.arithmeticOnlyCount -eq 1) 'Report did not survive serialization.'}
Must-Reject {& (Join-Path $PSScriptRoot 'ReviewNumericalReadinessBundle.ps1') -FeatureEvidencePath $fp -PriceEvidencePath (Join-Path $temp 'absent.json') -OutputDirectory $temp} 'Missing input accepted.'
$failed=@(Get-ChildItem -LiteralPath $temp -Filter 'numerical-readiness-bundle-*.json' | ForEach-Object {Get-Content $_.FullName -Raw | ConvertFrom-Json} | Where-Object status -eq 'FAILED_PARTIAL_REPORT')
Assert-Bundle ($failed.Count -eq 1 -and $failed[0].failureStage -eq 'INPUTS') 'Failure not checkpointed.'
Assert-Bundle ((Get-FileHash -LiteralPath $fp).Hash -eq $hash) 'Input was modified.'
Write-Host "PASS: $script:checks assertions. Offline fixtures retained: $temp"
