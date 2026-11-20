#Requires -Version 7.2
$ErrorActionPreference='Stop'
$root=(Resolve-Path "$PSScriptRoot/../..").Path
foreach($file in @('ops/windows/StartPaytmSupervisedLogin.ps1','ops/windows/DeployPaytmSupervised.ps1','ops/automation/Collect-SupervisedLoginReport.ps1','ops/automation/Build-SupervisedReportJob.ps1','ops/automation/jobs/PaytmDenialRecovery.ps1')){
 $tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw "Parse failed: $file"}
 Write-Host "PARSE_OK $file"
}
& "$root/ops/automation/Build-SupervisedReportJob.ps1" -Check
Write-Host 'SUPERVISED_HANDOFF_PARSE_AND_ARTIFACT_VERIFIED'
