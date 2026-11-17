#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-health-scheduled-0f5818e2c97b4f209ddd8d6200f4595d.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmHealthAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmHealthKeyCustody.ps1','PaytmClockComparison.ps1','PaytmApplicationRoute.ps1','PaytmHealthActivation.ps1','PaytmHealthTokenCustody.ps1')){. (Join-Path $PSScriptRoot $n)}
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$healthToken=$null;$map=$null;$source=$null;$container=$null
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$route=@{Root=$root};$application=@{Docker=$null;Token=$null}
$directory='C:\ProgramData\MarketBrainPaytmHealth\token-custody';$staged='C:\ProgramData\MarketBrainPaytmHealth\work\token-'+$run+'.dpapi'
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force;$path=Join-Path $OutputDirectory "paytm-health-token-$run.json"
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;applicationCommands=[Collections.Generic.List[object]]::new();applicationDiscovery=$null;sourceHashes=@{};stagingCreated=$false;stageWorker=$null;freshWorker=$null;operatorDecryptionDenied=$false;stagedCipherRemoved=$false;containerUnchanged=$false;finalLocked=$false;elapsedSeconds=0;plaintextFileWritten=$false;taskInstalled=$false;ordersEnabled=$false}
function Save-Report {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 10))}
function Token-Step([string]$Name,[int]$Percent){$report.stage=$Name;Save-Report;Write-Progress -Activity 'Health token custody' -Status $Name -PercentComplete $Percent;Write-Host "[$Percent%] $Name"}
function Assert-TokenWorker($Value,[string]$Mode){
 if($Value.version -ne 1 -or $Value.runId -cne $run -or $Value.mode -cne $Mode -or $Value.failure){throw 'HEALTH_TOKEN_WORKER_NOT_ACCEPTED'}
 foreach($n in @('identityVerified','encrypted','authenticated','locked')){if($Value.$n -isnot [bool] -or -not $Value.$n){throw 'HEALTH_TOKEN_WORKER_NOT_ACCEPTED'}}
 if($Value.bootId -cne $before.bootId){throw 'HEALTH_TOKEN_APPLICATION_RESTARTED'}
}
try{
 Save-Report;Assert-PaytmCustodyController
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '1A4B1F8D4D92ADBDF0DBEDFC72970F4BF5A6E2F65E8189F2A45AB2065E181DAF'){throw 'HEALTH_TOKEN_EVIDENCE_MISMATCH'}
 Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 $owned=Read-PaytmHealthAccount;$k=Get-HealthKeyContract
 if($owned.sid -cne $k.sid -or $owned.runId -cne $k.accountRun -or -not (Get-LocalUser -SID $k.sid).Enabled){throw 'HEALTH_TOKEN_ACCOUNT_CHANGED'}
 $null=Assert-PaytmAccountPath $directory;$null=Assert-PaytmAccountPath $staged
 if((Test-Path -LiteralPath $directory) -or (Test-Path -LiteralPath $staged)){throw 'HEALTH_TOKEN_STORAGE_EXISTS'}
 foreach($n in @('InstallPaytmHealthTokenCustody.ps1','PaytmHealthTokenCustody.ps1','PaytmGatewayAccount.ps1','PaytmHealthAccount.ps1','PaytmHealthKeyCustody.ps1','PaytmGatewayKeyCustody.ps1','PaytmClockComparison.ps1','PaytmApplicationRoute.ps1','PaytmHealthActivation.ps1','PaperRuntimeDeployment.ps1','PaperRuntimeReview.ps1','PaperAccountReadReview.ps1','PaytmTunnelVerification.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath "$PSScriptRoot/$n").Hash}
 Token-Step 'VERIFY_LOCAL_APPLICATION_AND_LOCK' 10
 if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'HEALTH_TOKEN_DOCKER_OVERRIDE'}
 $application.Docker=Resolve-PaytmClockTool 'docker.exe'
 $context=Invoke-PaytmClockDocker $application.Docker @('context','show') $root
 $endpoint=Invoke-PaytmClockDocker $application.Docker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') $root
 if($endpoint -notmatch '^npipe://'){throw 'HEALTH_TOKEN_LOCAL_DOCKER_REQUIRED'}
 $container=Get-PaytmApplicationContainer;$containerId=$container.Id;$image=$container.Image;$started=$container.State.StartedAt
 $map=ConvertTo-PaperRuntimeEnvironment $container.Config.Env
 $healthToken=$map.MARKETBRAIN_PAYTM_HEALTH_TOKEN;$application.Token=$map.MARKETBRAIN_PAPER_READ_TOKEN
 if($healthToken -cnotmatch '^[A-Za-z0-9_-]{32,128}$' -or $healthToken -ceq $application.Token -or $map.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $map.MARKETBRAIN_PAYTM_ACCESS_TOKEN){throw 'HEALTH_TOKEN_CONFIGURATION'}
 $before=Invoke-PaytmHealthActivationRoute 'status';$container=$null;$map=$null
 Write-Host 'Store only the existing diagnostic HEALTH token encrypted for marketbrain-health. No broker/read token is provisioned, and no healthy route claim is submitted.'
 $password=Read-Host 'Existing WINDOWS marketbrain-health account password' -AsSecureString
 Token-Step 'PROTECTED_TOKEN_LIBRARY' 25
 $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop;$report.stagingCreated=$true;Save-Report
 Set-PaytmAccountDirectoryAcl $directory $k.sid
 $library=Join-Path $directory 'library.ps1';$bytes=[IO.File]::ReadAllBytes("$PSScriptRoot/PaytmHealthTokenCustody.ps1")
 $f=[IO.File]::Open($library,'CreateNew','Write','None');try{$f.Write($bytes,0,$bytes.Length)}finally{$f.Dispose()}
 if((Get-FileHash -LiteralPath $library).Hash -cne $report.sourceHashes['PaytmHealthTokenCustody.ps1']){throw 'HEALTH_TOKEN_SOURCE_CHANGED'}
 Token-Step 'ENCRYPT_AND_AUTHENTICATE_AS_HEALTH_ACCOUNT' 40
 $info=New-PaytmAccountProbeStartInfo $password 'marketbrain-health';$diag=@{};$report['stageDiagnostics']=$diag
 try{
  # Token travels in this child-only environment, never in script source, argv or a file.
  $info.EnvironmentVariables['MARKETBRAIN_HEALTH_CUSTODY_TRANSFER']=$healthToken
  $source=New-HealthTokenWorkerSource $run 'Stage'
  $report.stageWorker=Invoke-PaytmAccountProbeProcess $info $source $diag
 }finally{$source=$null;$info.EnvironmentVariables.Remove('MARKETBRAIN_HEALTH_CUSTODY_TRANSFER');$info.Password=$null}
 Save-Report;Assert-TokenWorker $report.stageWorker 'Stage'
 $null=Assert-PaytmAccountPath $staged
 if((Get-Item -LiteralPath $staged).Length -gt 4096){throw 'HEALTH_TOKEN_CIPHER_SIZE'}
 $cipher=[IO.File]::ReadAllBytes($staged)
 try{$unexpected=Unprotect-HealthToken $cipher;$unexpected=$null}catch{$report.operatorDecryptionDenied=$true}
 if(-not $report.operatorDecryptionDenied){throw 'HEALTH_TOKEN_OPERATOR_COULD_DECRYPT'}
 $target=Join-Path $directory 'health-token.dpapi'
 $f=[IO.File]::Open($target,'CreateNew','Write','None');try{$f.Write($cipher,0,$cipher.Length);$f.Flush($true)}finally{$f.Dispose()}
 $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($cipher));$cipher=$null
 if((Get-FileHash -LiteralPath $staged).Hash -cne $expected -or (Get-FileHash -LiteralPath $target).Hash -cne $expected){throw 'HEALTH_TOKEN_CIPHER_CHANGED'}
 Token-Step 'FRESH_PROCESS_DECRYPT_AUTHENTICATE_AND_LOCK' 75
 $info=New-PaytmAccountProbeStartInfo $password 'marketbrain-health';$diag=@{};$report['freshDiagnostics']=$diag
 try{$report.freshWorker=Invoke-PaytmAccountProbeProcess $info (New-HealthTokenWorkerSource $run 'Verify') $diag}finally{$info.Password=$null}
 Save-Report;Assert-TokenWorker $report.freshWorker 'Verify'
 $again=Get-PaytmApplicationContainer;$againMap=ConvertTo-PaperRuntimeEnvironment $again.Config.Env
 if($again.Id -cne $containerId -or $again.Image -cne $image -or $again.State.StartedAt -cne $started -or $againMap.MARKETBRAIN_PAYTM_HEALTH_TOKEN -cne $healthToken){throw 'HEALTH_TOKEN_APPLICATION_CHANGED'}
 $report.containerUnchanged=$true;$again=$null;$againMap=$null
 $after=Invoke-PaytmHealthActivationRoute 'status'
 if($after.bootId -cne $before.bootId){throw 'HEALTH_TOKEN_APPLICATION_RESTARTED'};$report.finalLocked=$true
 $null=Assert-PaytmAccountPath $staged
 if((Get-FileHash -LiteralPath $staged).Hash -cne $expected){throw 'HEALTH_TOKEN_CIPHER_CHANGED'}
 [IO.File]::Delete($staged);$report.stagedCipherRemoved=$true
 Write-PaytmAccountNewJson (Join-Path $directory 'custody-state.json') @{version=1;runId=$run;sid=$k.sid;purpose='DIAGNOSTIC_HEALTH_ONLY';containerId=$containerId;image=$image;bootId=$before.bootId;protection='DPAPI_CURRENT_USER';taskInstalled=$false}
 $report.status='HEALTH_TOKEN_CUSTODY_PASSED_COLLECTOR_PENDING';$report.stage='COMPLETE'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(HEALTH_TOKEN|HEALTH_ACTIVATION|KEY|ACCOUNT|HEALTH_ACCOUNT|APP_ROUTE|CLOCK)_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_TOKEN_SETUP_FAILED'}
 $e=$_.Exception.GetBaseException();$report.failureDetails=@{type=$e.GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;hresult=$e.HResult}
}finally{
 if($null -ne $password){$password.Dispose()};$healthToken=$null;$application.Token=$null;$source=$null;$map=$null;$container=$null;$again=$null;$againMap=$null
 Save-Report;Write-Progress -Activity 'Health token custody' -Completed;Write-Host "[100%] $($report.status)";Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Share the report before retrying. Keep the account and token-custody directory intact.'}
