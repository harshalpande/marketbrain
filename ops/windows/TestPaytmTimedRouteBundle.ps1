#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-timing-guard-b435aa1bbc1d4b5eb6163574525cc27d.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$docker=$null;$started=$false
$name='marketbrain-timing-verification-'+$run;$tag='marketbrain-timing-verification:'+ $run
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-timed-route-'+$run+'.json')
$r=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;elapsedSeconds=0;sourceHashes=@{};build=$null;process=$null;result=$null;runningApplicationChanged=$false;ordersEnabled=$false;containerRemoved=$false;verificationImage=$tag}
function Save-TimedRoute {$r.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
try{
 Save-TimedRoute
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'C62CA3A41DBD4721AD408B356F5B871F4899C7FEFA9A18204AC11762F140E5D4'){throw 'TIMED_ROUTE_EVIDENCE_MISMATCH'}
 if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'TIMED_ROUTE_DOCKER_OVERRIDE'}
 $docker=(Get-Command docker -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $context=Invoke-EvaluationProcess $docker @('context','show') 10
 if($context.exitCode -ne 0){throw 'TIMED_ROUTE_DOCKER_CONTEXT'}
 $endpoint=Invoke-EvaluationProcess $docker @('context','inspect',$context.stdout.Trim(),'--format','{{.Endpoints.docker.Host}}') 10
 if($endpoint.exitCode -ne 0 -or $endpoint.stdout.Trim() -notmatch '^npipe://'){throw 'TIMED_ROUTE_LOCAL_DOCKER_REQUIRED'}
 $files=@('marketbrain-service/pom.xml','marketbrain-service/Dockerfile.paytm-timing-verification','ops/windows/TestPaytmTimedRouteBundle.ps1','ops/windows/NumericalEvaluationEngineering.ps1','ops/windows/NumericalHistoryEvidence.ps1')
 foreach($n in @('PaytmDiagnosticTimingGuard','PaytmApplicationRoute','PaytmApplicationRouteController','PaytmGatewayTransport')){$files+='marketbrain-service/src/main/java/in/marketbrain/marketdata/paytm/'+$n+'.java'}
 foreach($n in @('PaytmDiagnosticTimingVerification','PaytmApplicationRouteTest','PaytmTimedRouteIntegrationTest','PaytmGatewayTransportTest','PaytmRouteVerification','PaytmTimedRouteReport')){$files+='marketbrain-service/src/test/java/in/marketbrain/marketdata/paytm/'+$n+'.java'}
 foreach($file in $files){$r.sourceHashes[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}
 Write-Host '[10%] Build isolated verification image; existing application and database are untouched'
 Write-Progress -Activity 'Timed diagnostic route verification' -PercentComplete 10 -Status 'Build test image (dependencies may download)'
 $r.build=Invoke-EvaluationProcess $docker @('build','--progress=plain','-f',(Join-Path $root 'marketbrain-service/Dockerfile.paytm-timing-verification'),'-t',$tag,(Join-Path $root 'marketbrain-service')) 300;Save-TimedRoute
 if($r.build.timedOut -or $r.build.exitCode -ne 0){throw 'TIMED_ROUTE_BUILD_FAILED'}
 Write-Host '[65%] Run tests offline: no external network, ports, mounts or application access'
 Write-Progress -Activity 'Timed diagnostic route verification' -PercentComplete 65 -Status 'Spring, timing, controller and proxy-only tests'
 $started=$true
 $r.process=Invoke-EvaluationProcess $docker @('run','--rm','--name',$name,'--label',('marketbrain.verification.run='+$run),'--network','none','--memory','1g','--cpus','2',$tag) 120;Save-TimedRoute
 if($r.process.timedOut -or $r.process.exitCode -ne 0){throw 'TIMED_ROUTE_TEST_FAILED'}
 $line=@($r.process.stdout -split '\r?\n'|Where-Object {$_ -match '^\{"status"'})[-1]
 $r.result=$line|ConvertFrom-Json
 if($r.result.status -cne 'TIMED_ROUTE_INTEGRATION_TESTS_PASSED_DEPLOYMENT_PENDING' -or $r.result.junitTests -ne 20 -or $r.result.guardAssertions -ne 39 -or $r.result.liveHealthProviderConnected -ne $false -or $r.result.runningApplicationChanged -ne $false -or $r.result.ordersEnabled -ne $false){throw 'TIMED_ROUTE_RESULT_INVALID'}
 $r.status='TIMED_ROUTE_INTEGRATION_TESTS_PASSED_DEPLOYMENT_PENDING'
}catch{$r.failure=$_.Exception.Message}
finally{
 if($started){try{
  $inspect=Invoke-EvaluationProcess $docker @('ps','-a','--filter',('name=^/'+$name+'$'),'--format','{{.ID}}') 10
  if($inspect.exitCode -ne 0){throw 'TIMED_ROUTE_CLEANUP_QUERY_FAILED'}
  if($inspect.stdout.Trim()){
   $label=Invoke-EvaluationProcess $docker @('inspect','--format','{{index .Config.Labels "marketbrain.verification.run"}}',$name) 10
   if($label.exitCode -ne 0 -or $label.stdout.Trim() -cne $run){throw 'TIMED_ROUTE_CLEANUP_OWNERSHIP'}
   $remove=Invoke-EvaluationProcess $docker @('rm','-f',$name) 15
   if($remove.exitCode -ne 0){throw 'TIMED_ROUTE_CLEANUP_FAILED'}
  }
  $r.containerRemoved=$true
 }catch{$r.cleanupFailure=$_.Exception.Message}}
 if($r.failure -or $r.cleanupFailure){$r.status='REVIEW_REQUIRED'}
 Save-TimedRoute;Write-Progress -Activity 'Timed diagnostic route verification' -Completed;Write-Progress -Activity 'Numerical evaluation engineering' -Completed
 Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"
}
if($r.status -eq 'REVIEW_REQUIRED'){throw 'Share the JSON. Do not rebuild the main application.'}
