#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-time-repair-b0bbe132fade4898bc90ea64d6659f38.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-timing-guard-'+$run+'.json')
$r=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;elapsedSeconds=0;sourceHashes=@{};compiler=$null;process=$null;result=$null;applicationWired=$false;ordersEnabled=$false;settingsChanged=$false}
function Save-Timing {$r.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
try{
 Save-Timing
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '90DDA40CB92E3E808275B11E546367F341D612155C1C324859B9D2480470158C'){throw 'TIMING_GUARD_EVIDENCE_MISMATCH'}
 $source=Join-Path $root 'marketbrain-service\src\main\java\in\marketbrain\marketdata\paytm\PaytmDiagnosticTimingGuard.java'
 $test=Join-Path $root 'marketbrain-service\src\test\java\in\marketbrain\marketdata\paytm\PaytmDiagnosticTimingVerification.java'
 foreach($file in @($PSCommandPath,$source,$test,(Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1'),(Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1'))){$r.sourceHashes[[IO.Path]::GetFileName($file)]=(Get-FileHash -LiteralPath $file).Hash}
 Write-Host '[10%] Native JDK verification only; no service, network, database or broker calls'
 $javac=(Get-Command javac -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $java=Join-Path (Split-Path $javac -Parent) 'java.exe'
 if(-not (Test-Path -LiteralPath $java -PathType Leaf)){throw 'Matching java.exe beside javac required'}
 $classes=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-timing-'+$run)
 $null=New-Item -ItemType Directory -Path $classes
 Write-Progress -Activity 'Java timing guard verification' -PercentComplete 20 -Status 'Compile isolated guard and fixtures'
 $r.compiler=Invoke-EvaluationProcess $javac @('-J-Xmx256m','--release','21','-d',$classes,$source,$test) 60;Save-Timing
 if($r.compiler.timedOut -or $r.compiler.exitCode -ne 0){throw 'TIMING_GUARD_COMPILATION_FAILED'}
 Write-Host '[60%] Clock jumps, stale health, expiry, replay, restart and diagnostic budget'
 Write-Progress -Activity 'Java timing guard verification' -PercentComplete 60 -Status 'Run deterministic fake-clock scenarios'
 $r.process=Invoke-EvaluationProcess $java @('-Xmx128m','-cp',$classes,'in.marketbrain.marketdata.paytm.PaytmDiagnosticTimingVerification') 30;Save-Timing
 if($r.process.timedOut -or $r.process.exitCode -ne 0){throw 'TIMING_GUARD_VERIFICATION_FAILED'}
 $r.result=$r.process.stdout|ConvertFrom-Json
 if($r.result.status -cne 'TIMING_GUARD_ENGINEERING_PASSED_INTEGRATION_PENDING' -or $r.result.checks -ne 39 -or $r.result.networkCalls -ne 0 -or $r.result.ordersEnabled -ne $false -or $r.result.applicationWired -ne $false){throw 'TIMING_GUARD_RESULT_INVALID'}
 $r.status='TIMING_GUARD_ENGINEERING_PASSED_INTEGRATION_PENDING'
}catch{$r.failure=$_.Exception.Message}
finally{Save-Timing;Write-Progress -Activity 'Java timing guard verification' -Completed;Write-Progress -Activity 'Numerical evaluation engineering' -Completed;Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"}
if($r.failure){throw 'Share the JSON; do not rebuild or restart the application.'}
