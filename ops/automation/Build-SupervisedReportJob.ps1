#Requires -Version 7.2
param([switch]$Check)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Collect-SupervisedLoginReport.ps1'))
$target=Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'
if($Check){if([IO.File]::ReadAllText($target).Replace("`r`n","`n") -cne $source.Replace("`r`n","`n")){throw 'SUPERVISED_REPORT_ARTIFACT_DRIFT'}}
else{[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))}
