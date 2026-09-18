#Requires -Version 5.1
# Offline fixtures only. No service/DB/provider/model is called.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')
$calendar=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json') -Raw | ConvertFrom-Json
$script:calendarChecks=0
function Assert-Calendar([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:calendarChecks++}
function Copy-CalendarObject($Value){$Value | ConvertTo-Json -Depth 16 | ConvertFrom-Json}
$sessions=@(Get-NumericalCalendarSessions $calendar)
Assert-Calendar ('2026-01-15' -notin $sessions) 'Election closure missing.'
Assert-Calendar ('2026-02-01' -in $sessions) 'Sunday Budget session missing.'
Assert-Calendar ('2025-10-21' -in $sessions) 'Muhurat live session missing.'
Assert-Calendar ('2025-10-22' -notin $sessions) 'Holiday included.'
Assert-Calendar ('2026-02-07' -notin $sessions) 'Routine Saturday included.'
Assert-Calendar (@($sessions | Select-Object -Unique).Count -eq $sessions.Count) 'Duplicate session.'
function New-CalendarFixture {
    $bars=@(for($i=0;$i -lt $sessions.Count;$i++){[pscustomobject]@{candleId=$i+1;date=$sessions[$i];source='UPSTOX';excluded=$false}})
    $dates=@('2026-04-10','2026-05-08','2026-06-05')
    $rows=@(foreach($date in $dates){
        $window=@($bars | Where-Object {$_.date -le $date} | Select-Object -Last 252)
        [pscustomobject]@{decisionDate=$date;status='FEATURES_ONLY_CALENDAR_UNVERIFIED';featureFrom=$window[0].date;observationCount=252;sourceCandleIds=@($window.candleId);features=[pscustomobject]@{fixtureOnly=$true}}
    })
    [pscustomobject]@{
        version='NUMERICAL_FEATURE_EVIDENCE_V1';status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917'
        snapshot=[pscustomobject]@{
            status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';payloadSha256=('a'*64);partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0
            payload=[pscustomobject]@{
                version='OBSERVED_252_FEATURE_SNAPSHOT_V1';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917';datasetManifestHash=('b'*64)
                asOf='2026-06-05';windowFrom='2024-06-06';decisionDates=$dates
                instruments=@([pscustomobject]@{instrumentId=1;symbol='FIXTURE';rawRowCount=$bars.Count;truncated=$false;canonicalBars=$bars;rows=$rows})
            }
        }
    }
}
$clean=Get-NumericalFeatureCalendarReview (New-CalendarFixture) $calendar
Assert-Calendar ($clean.matchedRowCount -eq 3 -and $clean.blockedRowCount -eq 0) 'Good windows rejected.'
Assert-Calendar (-not $clean.trainingAuthorized -and $clean.labelsGenerated -eq 0) 'Calendar authorized training/labels.'
foreach($case in @('missingId','duplicateId','excluded','reordered','wrongFrom','future','partial','upstream','missingSession','closedDay','outside','shortCalendar')){
    $e=New-CalendarFixture;$item=$e.snapshot.payload.instruments[0];$row=$item.rows[0]
    switch($case){
        missingId {$row.sourceCandleIds[0]=999999}
        duplicateId {$row.sourceCandleIds[0]=$row.sourceCandleIds[1]}
        excluded {$item.canonicalBars[20].excluded=$true}
        reordered {$swap=$row.sourceCandleIds[0];$row.sourceCandleIds[0]=$row.sourceCandleIds[1];$row.sourceCandleIds[1]=$swap}
        wrongFrom {$row.featureFrom='2025-04-01'}
        future {$row.sourceCandleIds[-1]=$item.canonicalBars[-1].candleId}
        partial {$e.snapshot.partial=$true}
        upstream {$row.features=$null;$row.status='INVALID_OBSERVATION'}
        missingSession {$id=$row.sourceCandleIds[100];$item.canonicalBars=@($item.canonicalBars | Where-Object {$_.candleId -ne $id})}
        closedDay {$bar=$item.canonicalBars | Where-Object date -eq '2026-01-16';$bar.date='2026-01-15'}
        outside {$e.snapshot.payload.decisionDates[0]='2025-03-28';$row.decisionDate='2025-03-28'}
        shortCalendar {$e.snapshot.payload.decisionDates[0]='2025-04-02';$row.decisionDate='2025-04-02'}
    }
    $review=Get-NumericalFeatureCalendarReview $e $calendar
    Assert-Calendar ($review.blockedRowCount -gt 0 -and -not $review.trainingAuthorized) "Bad window passed: $case"
}
foreach($case in @('duplicateSource','unknownSource','badBounds','sourceUrl','unknownVersion')){
    $c=Copy-CalendarObject $calendar
    switch($case){
        duplicateSource {$c.sources+=@($c.sources[0])}
        unknownSource {$c.closures[0].sourceId='UNKNOWN'}
        badBounds {$c.coverageFrom='2024-01-01'}
        sourceUrl {$c.sources[0].url='https://example.com/unverified.pdf'}
        unknownVersion {$c.version='NEW_UNREVIEWED'}
    }
    $failed=$false;try{[void](Get-NumericalCalendarSessions $c)}catch{$failed=$true}
    Assert-Calendar $failed "Bad calendar accepted: $case"
}
foreach($case in @('training','counter','barDuplicate','tooMany','malformedDate','dateMismatch')){
    $e=New-CalendarFixture
    switch($case){
        training {$e.snapshot.trainingAuthorized=$true}
        counter {$e.snapshot.modelCallCount='0'}
        barDuplicate {$e.snapshot.payload.instruments[0].canonicalBars[1].candleId=1}
        tooMany {$e.snapshot.payload.instruments=@($e.snapshot.payload.instruments[0])*5}
        malformedDate {$e.snapshot.payload.instruments[0].canonicalBars[0].date='nonsense'}
        dateMismatch {$e.snapshot.payload.instruments[0].rows[0].decisionDate='2026-04-09'}
    }
    $failed=$false;try{[void](Get-NumericalFeatureCalendarReview $e $calendar)}catch{$failed=$true}
    Assert-Calendar $failed "Invalid artifact accepted: $case"
}
# Collector contract: mock network to fail immediately if ever introduced.
function Invoke-RestMethod {throw 'Network forbidden in offline calendar review.'}
function Invoke-WebRequest {throw 'Network forbidden in offline calendar review.'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-calendar-tests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
$fixturePath=Join-Path $temp 'fixture.json'
[IO.File]::WriteAllText($fixturePath,((New-CalendarFixture)|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
$before=(Get-FileHash -LiteralPath $fixturePath).Hash
for($i=1;$i -le 2;$i++){& (Join-Path $PSScriptRoot 'ReviewNumericalFeatureCalendar.ps1') -EvidencePath $fixturePath -OutputDirectory $temp | Out-Null}
$reports=@(Get-ChildItem -LiteralPath $temp -Filter 'numerical-calendar-*.json')
Assert-Calendar ($reports.Count -eq 2) 'Rerun overwrote prior report.'
Assert-Calendar ((Get-FileHash -LiteralPath $fixturePath).Hash -eq $before) 'Input changed.'
foreach($file in $reports){
    $r=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    Assert-Calendar ($r.inputSha256 -eq $before -and $r.result.matchedRowCount -eq 3) 'Report hash/result incorrect.'
}
$failureDir=Join-Path $temp 'failure';$failed=$false
try{& (Join-Path $PSScriptRoot 'ReviewNumericalFeatureCalendar.ps1') -EvidencePath (Join-Path $temp 'missing.json') -OutputDirectory $failureDir | Out-Null}catch{$failed=$true}
Assert-Calendar $failed 'Missing input succeeded.'
$failure=Get-ChildItem -LiteralPath $failureDir -Filter '*.json' | Select-Object -First 1
$r=Get-Content -LiteralPath $failure.FullName -Raw | ConvertFrom-Json
Assert-Calendar ($r.status -eq 'FAILED_PARTIAL_REPORT' -and $r.failureStage -eq 'READ_INPUT') 'Partial failure evidence absent.'
Write-Host "PASS: $script:calendarChecks assertions. Offline fixtures retained: $temp"
