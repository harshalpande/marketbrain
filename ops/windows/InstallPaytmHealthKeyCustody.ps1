#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$AccountReportPath='C:\MarketBrainData\Review\paytm-health-account-4f60b36179694f8c9d54aae847bd8e05.json',
 [string]$PreparationPath='C:\MarketBrainData\Review\paytm-clock-key-preparation-c192c546fbc2470f961341ea21f52266.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmHealthAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmTunnelVerification.ps1','PaytmHealthKeyCustody.ps1')){. (Join-Path $PSScriptRoot $n)}
$c=Get-HealthKeyContract;$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$password=$null;$bytes=$null;$window=$null;$started=$false;$childPath=$null
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory "paytm-health-key-custody-$run.json"
$r=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;sourceHashes=@{};accountSid=$c.sid;stagingCreated=$false;stagedCopyRemoved=$false;emptyProbe=$null;worker=$null;workerExit=$null;workerStopped=$false;fresh=$null;operatorSigningDeniedBefore=$false;operatorSigningDeniedAfter=$false;elapsedSeconds=0;vpsContacted=$false;taskInstalled=$false;ordersEnabled=$false;serviceChanged=$false}
function Save-HealthCustody {$r.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 10))}
function Step-HealthCustody([string]$Stage,[int]$Percent){$r.stage=$Stage;Save-HealthCustody;Write-Progress -Activity 'Clock key custody' -Status $Stage -PercentComplete $Percent;Write-Host "[$Percent%] $Stage"}
function Write-HealthCustodyFile([string]$Target,[byte[]]$Data){
 $null=Assert-PaytmAccountPath $Target;$f=[IO.File]::Open($Target,'CreateNew','Write','None')
 try{$f.Write($Data,0,$Data.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Read-HealthWorker {
 $null=Assert-PaytmAccountPath $childPath
 if((Get-Item -LiteralPath $childPath).Length -gt 8192){throw 'HEALTH_KEY_REPORT_SIZE'}
 $v=Get-Content -LiteralPath $childPath -Raw|ConvertFrom-Json
 if($v.version -ne 1 -or $v.runId -cne $run){throw 'HEALTH_KEY_REPORT_BINDING'}
 $v
}
try{
 Save-HealthCustody;Assert-PaytmCustodyController
 if((Get-FileHash -LiteralPath $AccountReportPath).Hash -cne '164187ED3B1819473C204B3D1F0C3360D7D076719304029F5A784BE8D917D90B' -or (Get-FileHash -LiteralPath $PreparationPath).Hash -cne '6DDEB3B0B3DAFC9F67E4D6FFF8DAD671D57860B3ECD944778E489FBE4400D2DE'){throw 'HEALTH_KEY_EVIDENCE_MISMATCH'}
 Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 $saved=Read-PaytmHealthAccount
 if($saved.sid -cne $c.sid -or $saved.runId -cne $c.accountRun -or -not (Get-LocalUser -SID $c.sid).Enabled){throw 'HEALTH_KEY_ACCOUNT_CHANGED'}
 $agent=Get-Service ssh-agent
 if($agent.Status -ne 'Running' -or $agent.StartType -ne 'Automatic'){throw 'HEALTH_KEY_AGENT_NOT_READY'}
 foreach($tool in @('ssh-add.exe')){if(-not (Test-Path -LiteralPath "C:\Windows\System32\OpenSSH\$tool" -PathType Leaf)){throw 'HEALTH_KEY_TOOL_MISSING'}}
 $null=Assert-PaytmAccountPath $c.root
 if(Test-Path -LiteralPath $c.root){throw 'HEALTH_KEY_STAGING_EXISTS'}
 $prep=Get-Content -LiteralPath $PreparationPath -Raw|ConvertFrom-Json
 $original=Assert-PaytmAccountPath $prep.privateKeyPath
 $f=[IO.File]::Open($original,'Open','Read','Read')
 try{
  if($f.Length -lt 100 -or $f.Length -gt 16384){throw 'HEALTH_KEY_INPUT_SIZE'}
  $bytes=[byte[]]::new([int]$f.Length);$offset=0
  while($offset -lt $bytes.Length){$n=$f.Read($bytes,$offset,$bytes.Length-$offset);if($n -le 0){throw 'HEALTH_KEY_INPUT_TRUNCATED'};$offset+=$n}
 }finally{$f.Dispose()}
 $v=Assert-PaytmEncryptedKey $bytes $c.blob
 if(-not $v.encrypted -or $v.fingerprint -cne $c.fingerprint){throw 'HEALTH_KEY_INPUT_IDENTITY'}
 $copies=@{'PaytmGatewayKeyCustody.ps1'='parser.ps1';'PaytmTunnelVerification.ps1'='native.ps1';'PaytmHealthKeyCustody.ps1'='health.ps1';'PaytmHealthKeyWorker.ps1'='worker.ps1'}
 foreach($n in @('InstallPaytmHealthKeyCustody.ps1','PaytmGatewayAccount.ps1','PaytmHealthAccount.ps1')+@($copies.Keys)){$r.sourceHashes[$n]=(Get-FileHash -LiteralPath "$PSScriptRoot/$n").Hash}
 $null=New-HealthKeyWindowInfo $null
 Write-Host 'This imports ONLY the clock key into the dedicated health account. A new CLOCK KEY window asks for its SSH passphrase twice. No VPS connection or task is started.'
 $password=Read-Host 'Existing WINDOWS marketbrain-health account password (not the clock-key passphrase)' -AsSecureString
 Step-HealthCustody 'EXACT_ACCOUNT_EMPTY_AGENT' 10
 $info=New-PaytmAccountProbeStartInfo $password 'marketbrain-health';$diag=@{}
 try{$r.emptyProbe=Invoke-PaytmAccountProbeProcess $info (New-PaytmAccountProbeSource $c.sid $run 'C:\ProgramData\MarketBrainPaytmHealth') $diag}finally{$info.Password=$null}
 Save-HealthCustody;Assert-PaytmAccountProbe $r.emptyProbe $run
 Step-HealthCustody 'PROTECTED_ENCRYPTED_STAGING' 25
 $saved=Read-PaytmHealthAccount
 if($saved.sid -cne $c.sid -or $saved.runId -cne $c.accountRun -or (Test-Path -LiteralPath $c.root)){throw 'HEALTH_KEY_TARGET_CHANGED'}
 $null=New-Item -ItemType Directory -Path $c.root -ErrorAction Stop;$r.stagingCreated=$true;Save-HealthCustody
 Set-PaytmAccountDirectoryAcl $c.root $c.sid
 foreach($n in $copies.Keys){
  $target=Join-Path $c.root $copies[$n];Write-HealthCustodyFile $target ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $n)))
  if((Get-FileHash -LiteralPath $target).Hash -cne $r.sourceHashes[$n]){throw 'HEALTH_KEY_SOURCE_CHANGED'}
 }
 $pub=Join-Path $c.root 'clock.pub';Write-HealthCustodyFile $pub ([Text.Encoding]::ASCII.GetBytes('ssh-ed25519 '+$c.blob+"`n"))
 Write-PaytmAccountNewJson (Join-Path $c.root 'plan.json') @{runId=$run;sid=$c.sid}
 $private=Join-Path $c.root 'clock.openssh';Write-HealthCustodyFile $private $bytes;Set-PaytmPrivateKeyAcl $private $c.sid
 $hash=(Get-FileHash -LiteralPath $private).Hash
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $false;$r.operatorSigningDeniedBefore=$true
 $childPath='C:\ProgramData\MarketBrainPaytmHealth\work\key-custody-'+$run+'.json'
 $null=Assert-PaytmAccountPath $childPath;if(Test-Path -LiteralPath $childPath){throw 'HEALTH_KEY_REPORT_EXISTS'}
 Step-HealthCustody 'CLOCK_KEY_WINDOW' 40
 $window=[Diagnostics.Process]::new();$window.StartInfo=New-HealthKeyWindowInfo $password
 Write-Host 'Switch to the new CLOCK KEY window and enter the clock-key passphrase at both prompts. This window needs no input.'
 $started=$window.Start();if(-not $started){throw 'HEALTH_KEY_WINDOW_START'}
 $wait=[Diagnostics.Stopwatch]::StartNew()
 while(-not $window.WaitForExit(1000)){
  if($wait.Elapsed.TotalSeconds -gt 480){throw 'HEALTH_KEY_WINDOW_TIMEOUT'}
  Write-Progress -Activity 'Clock key custody' -Status ("Waiting for CLOCK KEY window: {0:n0}/480 seconds" -f $wait.Elapsed.TotalSeconds) -PercentComplete 50
 }
 $r.workerStopped=$true;$r.workerExit=$window.ExitCode;$r.worker=Read-HealthWorker;Save-HealthCustody
 if($r.workerExit -ne 0 -or $r.worker.failure -or $r.worker.stage -cne 'COMPLETE'){throw 'HEALTH_KEY_WORKER_FAILED'}
 foreach($field in @('identityVerified','importAttempted','imported','revocationVerified','reloadVerified')){if($r.worker.$field -isnot [bool] -or -not $r.worker.$field){throw 'HEALTH_KEY_WORKER_INCOMPLETE'}}
 Step-HealthCustody 'REMOVE_THIS_RUN_ENCRYPTED_COPY' 75
 $null=Assert-PaytmAccountPath $private
 if((Get-FileHash -LiteralPath $private).Hash -cne $hash){throw 'HEALTH_KEY_STAGED_COPY_CHANGED'}
 [IO.File]::Delete($private);$r.stagedCopyRemoved=$true
 Step-HealthCustody 'FRESH_ACCOUNT_SIGNING_AND_OPERATOR_ISOLATION' 85
 $info=New-PaytmAccountProbeStartInfo $password 'marketbrain-health';$diag=@{}
 try{$r.fresh=Invoke-PaytmAccountProbeProcess $info (New-HealthKeyFreshSource $run) $diag}finally{$info.Password=$null}
 Save-HealthCustody
 if($r.fresh.runId -cne $run -or $r.fresh.failure -or $r.fresh.identityVerified -ne $true -or $r.fresh.signingVerified -ne $true){throw 'HEALTH_KEY_FRESH_FAILED'}
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $false;$r.operatorSigningDeniedAfter=$true
 Write-PaytmAccountNewJson (Join-Path $c.root 'custody-state.json') @{version=1;runId=$run;sid=$c.sid;fingerprint=$c.fingerprint;privateFileRetained=$false;taskInstalled=$false}
 $r.status='HEALTH_KEY_CUSTODY_PASSED_SCHEDULED_ACCESS_PENDING';$r.stage='COMPLETE'
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(HEALTH_KEY|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_KEY_SETUP_FAILED'}
 $e=$_.Exception.GetBaseException();$r.failureDetails=@{type=$e.GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;nativeError=if($e -is [ComponentModel.Win32Exception]){$e.NativeErrorCode}else{$null}}
}finally{
 if($null -ne $window){
  try{if($started -and -not $window.HasExited){$window.Kill($true);$r.workerStopped=$window.WaitForExit(5000)}}catch{$r.workerStopped=$false;$r.failure='HEALTH_KEY_WINDOW_STOP_FAILED';$r.status='REVIEW_REQUIRED'}
  finally{$window.StartInfo.Password=$null;$window.Dispose()}
 }
 if($null -eq $r.worker -and $childPath -and (Test-Path -LiteralPath $childPath)){try{$r.worker=Read-HealthWorker}catch{}}
 if($null -ne $password){$password.Dispose()};if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}
 Save-HealthCustody;Write-Progress -Activity 'Clock key custody' -Completed
 Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"
}
if($r.failure){throw 'Share the report before retrying. Preserve the account, staging and agent keys; import may have partially completed.'}
