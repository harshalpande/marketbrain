# Offline only: fake HTTP responses and temporary evidence files. No service/provider/DB/model calls.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DailyQualityFollowUp.ps1')
$state=[pscustomobject]@{mode='ok';calls=@();checks=0}
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-daily-review-'+[guid]::NewGuid().ToString('N'))
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Failed: $Name"};$state.checks++}
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    if($Method -ne 'Get' -or $MaximumRedirection -ne 0 -or $Uri -notlike 'http://127.0.0.1:8080/*'){throw 'Unexpected request authority/method.'}
    $state.calls+=@($Uri)
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($Uri -like '*/runs/status?*'){
        $r=[pscustomobject]@{runId='eebff875-3621-4064-a2ea-9de0b269681e';status='COMPLETED';requestedFrom='2026-09-19';targetDate='2026-10-08';instruments=500;universeSnapshotId='68117add-3ebe-4681-82fc-ff5613ecd869'}
        if($state.mode -eq 'wrongRun'){$r.requestedFrom='2010-01-01'};return $r
    }
    if($Uri -like '*/quality?*'){
        if($Uri -notlike '*providerSpotCheck=false' -or $TimeoutSec -ne 180){throw 'Unexpected quality scope.'}
        $r=[pscustomobject]@{jobId='eebff875-3621-4064-a2ea-9de0b269681e';jobStatus='COMPLETED';requestedFrom='2026-09-19';requestedTo='2026-10-08';instrumentCount=500;providerSpotCheckRequested=$false;truncatedFindingCount=0;largeMoves=@([pscustomobject]@{symbol='POLICYBZR';tradingDate='2026-09-24';previousClose=1886.3;close=1207.2})}
        if($state.mode -eq 'expanded'){$r.largeMoves+=@($r.largeMoves[0])};return $r
    }
    if($Uri -like '*/universe-preview?asOf=2026-10-08'){
        if($TimeoutSec -ne 660){throw 'Unexpected feature timeout.'}
        if($state.mode -eq 'timeout'){throw [TimeoutException]::new('Synthetic timeout')}
        $items=@(foreach($i in 1..500){$short=$i -gt 487;$n=if($short){200}else{300};[pscustomobject]@{
            symbol=('FIXTURE'+$i);status=if($short){'INSUFFICIENT_HISTORY'}else{'ELIGIBLE'};requestedAsOf='2026-10-08';effectiveAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1'
            canonicalObservationCount=$n;eligibleObservationCount=$n;excludedObservationCount=0;databaseWritesPerformed=$false
            features=if($short){$null}else{[pscustomobject]@{fixture=1}};detail=if($short){'At least 252 eligible observations required.'}else{'Fixture eligible'}
        }})
        $r=[pscustomobject]@{status='REVIEW_REQUIRED';featureSetVersion='TECHNICAL_V1';requestedAsOf='2026-10-08';universeSnapshotId='68117add-3ebe-4681-82fc-ff5613ecd869';instrumentCount=500;instruments=$items;manifestHash='50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62';databaseWritesPerformed=$false;eligibleCount=487;staleCount=0;insufficientHistoryCount=13;noEligibleDataCount=0;featureVectorCount=487}
        switch($state.mode){
            writes {$r.databaseWritesPerformed=$true}
            missingFlag {$r.databaseWritesPerformed=$null}
            duplicate {$items[1].symbol=$items[0].symbol}
            future {$items[0].effectiveAsOf='2026-10-09'}
            counts {$r.eligibleCount=500}
            shortHistory {$items[499].eligibleObservationCount=300;$items[499].canonicalObservationCount=300}
            drift {$r.manifestHash='b'*64}
        };return $r
    }
    if($Uri -like '*/large-move-evidence?*symbol=POLICYBZR'){
        $r=[pscustomobject]@{jobId='eebff875-3621-4064-a2ea-9de0b269681e';findingCount=1;sourceRequestCount=1;resolutionsWritten=$false
            findings=@([pscustomobject]@{symbol='POLICYBZR';findingDate='2026-09-24';storedPreviousClose=1886.3;storedClose=1207.2;evidenceStatus='OFFICIAL_PRICES_MATCH';reviewPath='REVIEW_VERIFIED_EXCHANGE_MOVE'})}
        if($state.mode -eq 'unavailable'){$r.findings[0].evidenceStatus='SOURCE_UNAVAILABLE';$r.findings[0].reviewPath='KEEP_OPEN'}
        if($state.mode -eq 'resolutionWrite'){$r.resolutionsWritten=$true}
        return $r
    }
    throw 'Unexpected endpoint.'
}
foreach($mode in @('ok','wrongRun','expanded','timeout','writes','missingFlag','duplicate','future','counts','shortHistory','drift','unavailable','resolutionWrite')){
    $state.mode=$mode;$state.calls=@();$failed=$false;$dir=Join-Path $root $mode
    try{& (Join-Path $PSScriptRoot 'GetDailyQualityFollowUp.ps1') -OutputDirectory $dir|Out-Null}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -File -Filter '*.json')
    Check ($files.Count -eq 1) "$mode one report"
    $report=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    $success=$mode -in @('ok','drift','unavailable')
    Check ($failed -ne $success) "$mode expected result"
    Check (($success -and $report.status -ceq 'CAPTURED_REVIEW_REQUIRED') -or (-not $success -and $report.status -ceq 'FAILED_PARTIAL_REPORT')) "$mode persisted status"
    $expectedCalls=if($mode -eq 'wrongRun'){2}elseif($mode -eq 'expanded'){3}elseif($mode -in @('ok','drift','unavailable','resolutionWrite')){5}else{4}
    Check ($state.calls.Count -eq $expectedCalls) "$mode bounded requests without retry"
    Check (-not $report.resolutionWriteRequested -and -not $report.featurePersistenceRequested -and -not $report.orderActionRequested) "$mode no release"
    if($success){Check ($report.featureSummary.withheld -eq 13 -and @($report.featureSummary.withheldInstruments).Count -eq 13) "$mode withholding retained"}
    if($mode -eq 'drift'){Check (-not $report.featureSummary.manifestMatchesOriginalAutomation) 'drift disclosed'}
}
$failed=$false
try{& (Join-Path $PSScriptRoot 'GetDailyQualityFollowUp.ps1') -BaseUrl 'https://example.com' -OutputDirectory (Join-Path $root 'external')|Out-Null}catch{$failed=$true}
Check $failed 'external endpoint rejected'
Write-Host "PASS: $($state.checks) offline daily quality follow-up assertions. Evidence: $root"
