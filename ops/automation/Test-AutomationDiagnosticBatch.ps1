#requires -Version 7.2
$ErrorActionPreference='Stop'
$temp=Join-Path $env:TEMP ('mb-batch-fixture-'+[guid]::NewGuid().ToString('N'))
$savedLocal=$env:LOCALAPPDATA
$global:batchFixture=@{seconds=0;submits=@();results=0;sleeps=0;lostReply=$true}
function Write-AutomationState($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12))}
function Get-AutomationConfig($Path){@{role='controller'}}
function Get-FixtureWatch {[pscustomobject]@{Elapsed=[pscustomobject]@{TotalSeconds=0;TotalMinutes=0}}}
function Start-Sleep {param($Seconds)
 $global:batchFixture.seconds+=100
 $watch.Elapsed.TotalSeconds=$global:batchFixture.seconds
 $watch.Elapsed.TotalMinutes=$global:batchFixture.seconds/60
}
function Invoke-AutomationApi($Config,$Route,$Body){
 if($Route -eq '/submit'){
  $global:batchFixture.submits+=,$Body.id
  if($global:batchFixture.lostReply){$global:batchFixture.lostReply=$false;throw 'lost reply after server accepted'}
  return @{}
 }
 $global:batchFixture.results++
 @{job=@{id=$Body.id;kind='diagnostic';state='FAILED';result=@{reason='fixture failure'}}}
}
try{
 $null=New-Item -ItemType Directory -Path $temp
 $env:LOCALAPPDATA=$temp
 [IO.File]::WriteAllText((Join-Path $temp 'Automation.Common.ps1'),'# mocked transport only')
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Automation.BatchAssessment.ps1') -Destination $temp
 $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Start-AutomationDiagnosticBatch.ps1'))
 $text=$text.Replace('[Diagnostics.Stopwatch]::StartNew()','(Get-FixtureWatch)')
 $scriptPath=Join-Path $temp 'Start-AutomationDiagnosticBatch.ps1'
 [IO.File]::WriteAllText($scriptPath,$text)
 & $scriptPath -DurationMinutes 30 -IntervalSeconds 120 6>$null
 $reports=Join-Path $temp 'MarketBrainAutomation/reports'
 $b=Get-Content (Get-ChildItem $reports -Filter 'batch-*.json').FullName -Raw|ConvertFrom-Json
 if($global:batchFixture.submits.Count -lt 3 -or $global:batchFixture.submits[0] -ne $global:batchFixture.submits[1]){throw 'Lost submission reply created another job'}
 if($b.connectionErrors -ne 1 -or $b.jobs.Count -lt 2 -or @($b.jobs|Where-Object {$_.assessment.transportPassed}).Count){throw 'Failed jobs incorrectly passed or retries missing'}
 if($b.status -ne 'OBSERVATION_COMPLETE_REVIEW_FINDINGS' -or $b.pendingJobId){throw 'Batch did not finish cleanly'}
 foreach($j in $b.jobs){if(-not (Test-Path (Join-Path $reports ($j.id+'.json')))){throw 'Raw result missing'}}
 Write-Host 'PASS: lost-response idempotency, sequential continuation after failures, finite window, persisted raw and assessed results (simulated time/transport)'
}finally{
 $env:LOCALAPPDATA=$savedLocal
 $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-batch-fixture-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup'}
 if(Test-Path $full){Remove-Item -LiteralPath $full -Recurse -Force}
 Remove-Variable batchFixture -Scope Global
}
