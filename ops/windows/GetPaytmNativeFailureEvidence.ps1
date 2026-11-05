#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$DiagnosticReportPath='C:\MarketBrainData\Review\paytm-gateway-session-b38a9a376e164645a69459a90cd3f9f7.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1')){. (Join-Path $PSScriptRoot $name)}
$watch=[Diagnostics.Stopwatch]::StartNew();$c=Get-PaytmHostContract
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;elapsedSeconds=0;readOnly=$true;sourceHashes=@{};gatewayChanged=$false;taskStarted=$false;credentialsUsed=$false;ordersEnabled=$false;applicationAccessed=$false;underlyingOperationEstablished=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$script:nativeReportPath=Join-Path $OutputDirectory ('paytm-native-failure-'+$report.runId+'.json')
$lease=$null
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $DiagnosticReportPath
 if((Get-FileHash -LiteralPath $DiagnosticReportPath).Hash -cne '1AC0D72016F9BF053F94C8C99B40CCB717351A4A0411ED892BACA014C9524106'){throw 'NATIVE_REVIEWED_REPORT_MISMATCH'}
 $inputReport=Read-PaytmHostJson $DiagnosticReportPath 65536
 $report.reviewedRunId=$inputReport.runId
 $time=[DateTimeOffset]$inputReport.workerDiagnostics.files.'startup-failure.json'.lastWriteUtc
 $from=$time.AddMinutes(-5).ToUniversalTime().ToString('o');$to=$time.AddMinutes(5).ToUniversalTime().ToString('o')
 foreach($name in @('GetPaytmNativeFailureEvidence.ps1','ReadPaytmNativeFailure.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewaySession.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $null=Assert-PaytmAccountPath $c.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $report.stage='READ_CURRENT_FAILURE_AND_INSTALLED_HASHES';Write-Host '[20%] Reading saved failure and installed helper hashes.'
 Write-Progress -Activity 'Native health-check failure evidence' -Status $report.stage -PercentComplete 20
 $report.workerDiagnostics=Get-PaytmWorkerFailureEvidence
 $m=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.root 'manifest.json'))
 $report.installedFiles=@()
 foreach($name in @('native.dll','runner.ps1','transport.ps1')){
  $actual=(Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root $name))).Hash
  $expected=Get-PaytmEvidenceProperty $m.hashes $name
  if([string]$expected -cnotmatch '^[A-F0-9]{64}$'){throw 'NATIVE_MANIFEST_HASH_INVALID'}
  $report.installedFiles+=@{name=$name;actualSha256=$actual;manifestSha256=$expected;matchesManifest=($actual -ceq $expected)}
 }
 Write-PaytmSessionReport $script:nativeReportPath $report
 $report.stage='READ_BOUNDED_WINDOWS_EVENTS_AND_LOCAL_CURL_VERSION';Write-Host '[50%] Reading ten-minute Windows event window and executable metadata; local curl --version only.'
 Write-Progress -Activity 'Native health-check failure evidence' -Status $report.stage -PercentComplete 50
 # All script content comes from the reviewed checkout; only invariant timestamps
 # enter the wrapper. The PS5 subprocess bounds Event Log/signature queries as a whole.
 $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReadPaytmNativeFailure.ps1'))
 $code="& {`n"+$body+"`n} -StartUtc '"+$from+"' -EndUtc '"+$to+"'"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $result=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 90
 $report.nativeQuery=@{exitCode=$result.exitCode;elapsedSeconds=$result.elapsedSeconds;stderrCharacters=$result.stderr.Length}
 if($result.exitCode -ne 0 -or $result.stdout.Length -gt 40000){throw 'NATIVE_QUERY_FAILED_OR_OVERSIZE'}
 $report.nativeEvidence=$result.stdout|ConvertFrom-Json -ErrorAction Stop
 # Captured JSON is not a complete diagnostic when required observations failed.
 $e=$report.nativeEvidence
 $completeFiles=@($e.files).Count -eq 2
 foreach($name in @('curl.exe','powershell.exe')){
  $rows=@($e.files | Where-Object fileName -CEQ $name)
  if($rows.Count -ne 1){$completeFiles=$false;continue}
  $f=$rows[0]
  if(-not $f.present -or $f.errorType -or $f.stage -cne 'COMPLETE' -or $f.sha256 -cnotmatch '^[A-F0-9]{64}$' -or -not $f.signatureStatus -or -not $f.accessSddl){$completeFiles=$false}
 }
 $report.metadataComplete=$completeFiles
 if(-not $completeFiles){throw 'NATIVE_FILE_METADATA_INCOMPLETE'}
 $report.status='NATIVE_FAILURE_EVIDENCE_CAPTURED';$report.stage='COMPLETE'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(NATIVE|HOST|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'NATIVE_DIAGNOSTIC_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)}
}finally{
 if($lease){$lease.Dispose()}
 $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
 Write-PaytmSessionReport $script:nativeReportPath $report
 Write-Progress -Activity 'Native health-check failure evidence' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $script:nativeReportPath"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Native diagnostic capture needs review. Share the JSON; do not reset the gateway.'}
