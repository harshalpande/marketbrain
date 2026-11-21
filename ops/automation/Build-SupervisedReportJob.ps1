#Requires -Version 7.2
param([switch]$Check)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Collect-SupervisedLoginReport.ps1'))
$probe=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedBoundaryProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedUniverseProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedLifecycleProbe.ps1'))
$insertion=$probe+@'

if($Mode -eq 'FailureFixture'){
 $boundary=Invoke-SupervisedBoundaryProbe
 [IO.File]::WriteAllText($ResultPath,($boundary|ConvertTo-Json -Depth 6))
 if(-not $boundary.passed){exit 1}
 exit 0
}
if($Mode -eq 'Apply'){
 $universe=Invoke-SupervisedUniverseProbe
 [IO.File]::WriteAllText($ResultPath,($universe|ConvertTo-Json -Depth 6))
 if(-not $universe.passed){exit 1}
 $lifecycle=Invoke-SupervisedLifecycleProbe
 $batch=@{test='SUPERVISED_UNIVERSE_AND_LIFECYCLE';passed=$lifecycle.passed;ordersEnabled=$false;universe=$universe;lifecycle=$lifecycle}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $lifecycle.passed){exit 1}
 exit 0
}

'@
$source=$source.Replace("`$ErrorActionPreference='Stop'","`$ErrorActionPreference='Stop'"+"`n"+$insertion)
$target=Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'
if($Check){if([IO.File]::ReadAllText($target).Replace("`r`n","`n") -cne $source.Replace("`r`n","`n")){throw 'SUPERVISED_REPORT_ARTIFACT_DRIFT'}}
else{[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))}
