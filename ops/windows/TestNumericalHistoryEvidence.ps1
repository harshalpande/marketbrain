#Requires -Version 5.1
# Fully mocked HTTP; no live database, model or provider requests.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$testState=[pscustomobject]@{checks=0;calls=0;mode='normal'}
$run=[guid]'5bdbfcc1-d990-48d8-9e98-d4927596d917'
function Assert-History([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$testState.checks++}
function New-HistoryPage([int]$Offset=0) {
    $items=@(for($i=$Offset+1;$i -le [math]::Min(51,$Offset+50);$i++) {
        [pscustomobject]@{instrumentId=$i;symbol="TEST$i";persistedClassification=$(if($i -le 24){'INSUFFICIENT_HISTORY'}else{'LABELED'})
            persistedReason='fixture';effectiveAsOf='2026-06-05';rawRowsScanned=100;observedDates=100;nonexcludedDates=100;excludedDates=0
            firstObservedDate='2026-01-01';lastObservedDate='2026-06-05';receivedAfterDecisionCutoffRows=10;missingReceivedAtRows=0;nseRows=80;upstoxRows=20;truncated=$false}
    })
    [pscustomobject]@{version='NUMERICAL_HISTORY_COVERAGE_V1';status='REVIEW_REQUIRED';datasetRunId=$run.ToString();datasetManifestHash=('a'*64)
        asOf='2026-06-05';windowFrom=([datetime]'2026-06-05').AddDays(-729).ToString('yyyy-MM-dd');lookbackDays=730;offset=$Offset;limit=50;instrumentCount=51
        nextOffset=$(if($Offset -eq 0){50}else{$null});instruments=$items;partial=$false
        contract=[pscustomobject]@{version='NUMERICAL_SWING_20_V1_DRAFT';trainingAuthorized=$false};databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0;limitations='Fixture only'}
}
Assert-NumericalHistoryPage (New-HistoryPage) $run 0 730 ''
Assert-History $true 'Valid page rejected.'
Assert-NumericalHistoryPage (New-HistoryPage 50) $run 50 730 ('a'*64) 51
Assert-History $true 'Valid final page rejected.'
foreach($case in @('manifest','count','next','write','training','partial','window','negative','string','source','incomplete','cap')) {
    $p=New-HistoryPage
    switch($case){
        manifest {$p.datasetManifestHash='b'*64}
        count {$p.instrumentCount=52}
        next {$p.nextOffset=0}
        write {$p.databaseWritesPerformed=$true}
        training {$p.contract.trainingAuthorized=$true}
        partial {$p.partial=$true}
        window {$p.windowFrom=$p.asOf}
        negative {$p.instruments[0].observedDates=-1}
        string {$p.instrumentCount='51'}
        source {$p.instruments[0].nseRows=99}
        incomplete {$p.instruments=@($p.instruments[0])}
        cap {$p.instruments[0].truncated=$true}
    }
    $rejected=$false;try{Assert-NumericalHistoryPage $p $run 0 730 ('a'*64) 51}catch{$rejected=$true}
    Assert-History $rejected "Bad page accepted: $case"
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-history-tests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $testState.calls++
    Assert-History ($Method -eq 'Get' -and $MaximumRedirection -eq 0 -and $TimeoutSec -le 60) 'Unsafe HTTP request.'
    if($Uri -eq 'http://127.0.0.1:8080/actuator/health'){return [pscustomobject]@{status='UP'}}
    Assert-History ($Uri -match ('^http://127.0.0.1:8080/api/v1/training/numerical-history-coverage\?datasetRunId='+$run+'&offset=(0|50)&limit=50&lookbackDays=730$')) 'Wrong request scope.'
    $offset=if($Uri -match '&offset=50&'){50}else{0}
    if($offset -eq 50 -and $testState.mode -eq 'timeout'){throw 'SECRET_TEST_MARKER'}
    $p=New-HistoryPage $offset
    if($offset -eq 50 -and $testState.mode -eq 'duplicate'){$p.instruments[0].instrumentId=1}
    if($testState.mode -eq 'cap'){
        $p.partial=$true;$p.instruments[0].rawRowsScanned=2001;$p.instruments[0].nseRows=1981;$p.instruments[0].truncated=$true
    }
    return $p
}
$entry=Join-Path $PSScriptRoot 'GetNumericalHistoryEvidence.ps1'
foreach($mode in @('normal','cap','timeout','duplicate')) {
    $testState.mode=$mode;$testState.calls=0;$dir=Join-Path $root $mode
    $failed=$false;try{& $entry -DatasetRunId $run -OutputDirectory $dir}catch{$failed=$true;if($mode -in @('normal','cap')){throw}}
    Assert-History ($testState.calls -eq 3) 'Unexpected retry/call count.'
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json')
    Assert-History ($files.Count -eq 1) 'Expected one persisted report.'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw | ConvertFrom-Json
    if($mode -in @('timeout','duplicate')) {
        Assert-History ($failed -and $r.status -eq 'FAILED_PARTIAL_REPORT' -and $r.completedInstrumentCount -eq 50 -and $r.partial) 'Partial results lost/accepted.'
        Assert-History ($raw -notmatch 'SECRET_TEST_MARKER') 'Raw error body leaked.'
    }else{
        Assert-History (-not $failed -and $r.completedInstrumentCount -eq 51 -and $r.summary.persistedInsufficientHistoryCount -eq 24) 'Successful collection failed.'
        Assert-History (-not $r.summary.trainingAuthorized -and $r.pages.Count -eq 2) 'Unsafe summary.'
        $expected=if($mode -eq 'cap'){'PARTIAL_WINDOW_COVERAGE_REVIEW_REQUIRED'}else{'WINDOW_COVERAGE_REVIEW_REQUIRED'}
        Assert-History ($r.status -eq $expected) 'Capped evidence not distinguished.'
    }
}
$checkpoint=Join-Path $root 'checkpoint.json'
$snapshot=[pscustomobject]@{updatedAtUtc=$null;value='old'}
Save-NumericalHistoryReport $snapshot $checkpoint
$testState | Add-Member -NotePropertyName replaceCalls -NotePropertyValue 0
function Invoke-HistoryAtomicReplace([string]$Temporary,[string]$Path) {
    $testState.replaceCalls++
    if($testState.replaceCalls -le 2){throw [IO.IOException]::new('Simulated sharing violation',-2147024864)}
    [IO.File]::Replace($Temporary,$Path,[System.Management.Automation.Language.NullString]::Value)
}
$snapshot.value='new'
Save-NumericalHistoryReport $snapshot $checkpoint
Assert-History ($testState.replaceCalls -eq 3 -and (Get-Content $checkpoint -Raw | ConvertFrom-Json).value -eq 'new') 'Sharing violation retry failed.'
$testState.replaceCalls=0
function Invoke-HistoryAtomicReplace([string]$Temporary,[string]$Path) {
    $testState.replaceCalls++
    throw [IO.IOException]::new('Simulated sharing violation',-2147024864)
}
$failed=$false;try{$snapshot.value='pending';Save-NumericalHistoryReport $snapshot $checkpoint}catch{$failed=$true}
Assert-History ($failed -and $testState.replaceCalls -eq 6) 'Unbounded save retry.'
Assert-History ((Get-Content $checkpoint -Raw | ConvertFrom-Json).value -eq 'new') 'Old checkpoint damaged.'
$pending=@(Get-ChildItem -LiteralPath $root -Filter 'checkpoint.json.pending-*')
Assert-History ($pending.Count -eq 1 -and (Get-Content $pending[0].FullName -Raw | ConvertFrom-Json).value -eq 'pending') 'Recovery checkpoint lost.'
Write-Host "PASS: $($testState.checks) offline history assertions. Fixtures retained: $root"
