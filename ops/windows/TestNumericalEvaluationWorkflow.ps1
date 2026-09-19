#Requires -Version 5.1
# Developer tests: synthetic only; uses JDK and Windows PowerShell, never Docker/service.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$script:assertions=0
function Assert-Eval($Condition,[string]$Message){$script:assertions++;if(-not $Condition){throw $Message}}
function Reject-Eval([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action}catch{$caught=$true;$script:lastExpectedError=$_.Exception.Message};Assert-Eval $caught $Message}
$folder=Join-Path $PSScriptRoot ('..\..\marketbrain-service\target\evaluation-workflow-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'TestNumericalEvaluationEngineering.ps1') -Runtime Java -OutputDirectory $folder
$first=Get-ChildItem -LiteralPath $folder -Filter '*.json' | Select-Object -First 1
$hash=(Get-FileHash -LiteralPath $first.FullName).Hash
$report=Get-Content -LiteralPath $first.FullName -Raw | ConvertFrom-Json
Assert-EvaluationSmoke $report.javaResult
Assert-Eval ($report.status -eq 'SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED') 'Wrong envelope status.'
Assert-Eval (@(Get-ChildItem -LiteralPath $folder -File).Count -eq 1) 'Expected one file only.'
Assert-Eval ($report.process.exitCode -eq 0 -and -not $report.process.timedOut) 'Child failed.'
Assert-Eval ($report.sourceSha256 -match '^[A-F0-9]{64}$' -and $report.scriptSha256 -match '^[A-F0-9]{64}$' -and $report.helperSha256 -match '^[A-F0-9]{64}$') 'Missing hashes.'
foreach($case in @('status','unsafe','missing','duplicate','metric','nan','string','fixtureHash','guard','count','model','names','timing','contract','stringCount')){
    $bad=$report.javaResult | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    switch($case){
        status{$bad.status='PASSED'}unsafe{$bad.trainingAuthorized=$true}missing{$bad.checks=@($bad.checks|Select-Object -Skip 1)}
        duplicate{$bad.checks[1]=$bad.checks[0]}metric{$bad.metrics.equalDateWeighted.rmse=2.25}nan{$bad.metrics.rowWeighted.mae=[double]::NaN}
        string{$bad.metrics.rowWeighted.mae='2'}fixtureHash{$bad.checks[0].fixtureSha256='invalid'}guard{$bad.guard.status='REJECTED'}
        count{$bad.failedCheckCount=1}model{$bad.modelCallCount=1}names{$bad.checks[0].name='UNKNOWN'}
        timing{$bad.checks[0].elapsedMillis=-1}contract{$bad.metrics.contract.unit='FRACTION'}stringCount{$bad.checkCount='22'}
    }
    Reject-Eval {Assert-EvaluationSmoke $bad} "Accepted tampered report: $case"
}
& (Join-Path $PSScriptRoot 'TestNumericalEvaluationEngineering.ps1') -Runtime Java -OutputDirectory $folder
Assert-Eval (@(Get-ChildItem -LiteralPath $folder -Filter '*.json').Count -eq 2) 'Repeat run overwrote evidence.'
Assert-Eval ((Get-FileHash -LiteralPath $first.FullName).Hash -eq $hash) 'Original evidence changed.'
$powershell=Join-Path $PSHOME 'powershell.exe'
if(-not (Test-Path -LiteralPath $powershell)){$powershell=(Get-Command powershell -CommandType Application).Source}
function Encoded-Eval([string]$Text){[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Text))}
$result=Invoke-EvaluationProcess $powershell @('-NoProfile','-NonInteractive','-EncodedCommand',(Encoded-Eval '[Console]::Out.Write("out");[Console]::Error.Write("err");exit 7')) 10
Assert-Eval ($result.exitCode -eq 7 -and $result.stdout -eq 'out' -and $result.stderr -eq 'err') 'Process evidence missing.'
$result=Invoke-EvaluationProcess $powershell @('-NoProfile','-NonInteractive','-EncodedCommand',(Encoded-Eval 'Start-Sleep -Seconds 20')) 1
Assert-Eval ($result.timedOut -and $result.exitCode -eq -999 -and $result.elapsedSeconds -lt 10) 'Timeout was not bounded.'
Assert-Eval ((ConvertTo-EvaluationProcessArgument 'C:\some space\') -eq '"C:\some space\\"') 'Trailing slash quoting incorrect.'
Assert-Eval ((ConvertTo-EvaluationProcessArgument 'a"b') -eq '"a\"b"') 'Embedded quote escaping incorrect.'
# Mock command resolution only. A real failing native child must still leave one failed JSON.
function Get-Command { param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source=$powershell} }
$failedFolder=Join-Path $folder 'failed-child'
Reject-Eval {& (Join-Path $PSScriptRoot 'TestNumericalEvaluationEngineering.ps1') -Runtime Java -OutputDirectory $failedFolder} 'Failed child not propagated.'
$failureFile=Get-ChildItem -LiteralPath $failedFolder -Filter '*.json' | Select-Object -First 1
if(-not $failureFile){throw "No failed report: $script:lastExpectedError"}
$failed=Get-Content -LiteralPath $failureFile.FullName -Raw | ConvertFrom-Json
Assert-Eval ($failed.status -eq 'FAILED' -and $failed.failure -and $failed.process.exitCode -ne 0) 'Failed child evidence lost.'
Assert-Eval (-not $failed.trainingAuthorized -and $null -eq $failed.javaResult) 'Failure reported as validation success.'
$dockerFolder=Join-Path $folder 'docker-probe'
Reject-Eval {& (Join-Path $PSScriptRoot 'TestNumericalEvaluationEngineering.ps1') -Runtime Docker -OutputDirectory $dockerFolder} 'Failed Docker probe not propagated.'
$probeFile=Get-ChildItem -LiteralPath $dockerFolder -Filter '*.json' | Select-Object -First 1
$probeReport=Get-Content -LiteralPath $probeFile.FullName -Raw | ConvertFrom-Json
Assert-Eval ($probeReport.status -eq 'FAILED' -and $probeReport.runtimeProbe.exitCode -ne 0 -and $null -eq $probeReport.process) 'Probe failure evidence lost or child started.'
Write-Host "Evaluation workflow tests passed: $script:assertions assertions. Evidence: $folder"
