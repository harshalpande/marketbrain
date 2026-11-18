#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmHealthAccount.ps1','PaytmHealthKeyCustody.ps1','PaytmHealthScheduledProbe.ps1','PaytmHealthBatchLogon.ps1')){. (Join-Path $PSScriptRoot $n)}
. (Join-Path $PSScriptRoot 'PaytmHealthScheduledToken.ps1')
$run='a'*32;$c=Get-HealthScheduledProbeContract $run;$k=Get-HealthScheduledKeyContract;$count=0
function GoodTask {
 [pscustomobject]@{TaskName=$c.name;TaskPath=$c.path;Description=('MarketBrain temporary health clock probe '+$run);Principal=[pscustomobject]@{UserId=$k.accountSid;LogonType='Password';RunLevel='Limited'};Actions=@([pscustomobject]@{Execute=$c.executable;Arguments=(Get-HealthScheduledArguments $run);WorkingDirectory=$c.directory});Triggers=@();Settings=[pscustomobject]@{Enabled=$false;MultipleInstances='IgnoreNew';RestartCount=0;AllowDemandStart=$true;AllowHardTerminate=$true;WakeToRun=$false;StartWhenAvailable=$false;RunOnlyIfNetworkAvailable=$false;RunOnlyIfIdle=$false;DisallowStartIfOnBatteries=$false;StopIfGoingOnBatteries=$false;ExecutionTimeLimit='PT2M'}}
}
Assert-HealthProbeTask (GoodTask) $run $false;$count++
foreach($case in @('admin','trigger','arguments','enabled','timeout')){
 $t=GoodTask
 switch($case){admin{$t.Principal.RunLevel='Highest'} trigger{$t.Triggers=@('unexpected')} arguments{$t.Actions[0].Arguments='unexpected'} enabled{$t.Settings.Enabled=$true} timeout{$t.Settings.ExecutionTimeLimit='PT5M'}}
 $caught=$false;try{Assert-HealthProbeTask $t $run $false}catch{$caught=$true};if(-not $caught){throw "TASK_ACCEPTED_$case"};$count++
}
$before=[pscustomobject]@{allow=@('S-1-5-32-544');deny=@()}
$after=[pscustomobject]@{allow=@('S-1-5-32-544',$k.accountSid);deny=@()}
Assert-HealthBatchPolicyDelta $before $after;$count++
foreach($bad in @([pscustomobject]@{allow=@($k.accountSid);deny=@()},[pscustomobject]@{allow=$after.allow;deny=@('S-1-1-0')},[pscustomobject]@{allow=@($after.allow)+@('S-1-5-32-545');deny=@()})){
 $caught=$false;try{Assert-HealthBatchPolicyDelta $before $bad}catch{$caught=$true};if(-not $caught){throw 'POLICY_DRIFT_ACCEPTED'};$count++
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('health scheduled fixtures '+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $root
# The portable PS7 test runtime lacks compiler reference assemblies. Compile the
# identical interop code using native PS5.1; reject a wrong SID before any LSA call.
$batchText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmHealthBatchLogon.ps1'))
$code=[regex]::Match($batchText,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if(-not $code){throw 'INTEROP_SOURCE_MISSING'}
$cs=Join-Path $root 'policy.cs';[IO.File]::WriteAllText($cs,$code)
$compile=Join-Path $root 'compile.ps1'
[IO.File]::WriteAllText($compile,@'
param($Source)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText($Source))
$caught=$false;try{[MarketBrainHealthBatchPolicyV1]::Grant('S-1-5-21-3041730714-102984520-3202743044-1010')}catch{$caught=$_.Exception.ToString().Contains('SCHEDULE_POLICY_SID')}
if(-not $caught){throw 'GATEWAY_GRANT_ACCEPTED'}
'@)
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $compile $cs
if($LASTEXITCODE -ne 0){throw 'INTEROP_VALIDATION_FAILED'};$count++
foreach($case in @('success','wrongNonce','signFailure','interactive','identityFailure','tokenSuccess','decryptFailure','authFailure','collectorSuccess','collectorFailure','collectorException')){
 $dir=Join-Path $root $case;$null=New-Item -ItemType Directory $dir
 [IO.File]::WriteAllText((Join-Path $dir 'parser.ps1'),'')
 [IO.File]::WriteAllText((Join-Path $dir 'native.ps1'),'')
 $mock=@'
function Assert-HealthKeyIdentity {if('__CASE__' -ceq 'identityFailure'){throw 'HEALTH_KEY_IDENTITY'}}
function Assert-HealthKeyAgent {}
function Get-FileHash {param($LiteralPath) [pscustomobject]@{Hash='C93B10DF35EBE8ED703D115CD192DAD13547CC30B35C7069B5EFEF396AB349DC'}}
function Get-Process {param($Id) [pscustomobject]@{SessionId=if('__CASE__' -ceq 'interactive'){1}else{0}}}
function Assert-PaytmSigningResult {param($Result,$Expected) if($Result.ExitCode -ne 0){throw 'KEY_SIGNING_RESULT_UNEXPECTED'}}
function Invoke-PaytmCustodyNative {param($Tool,[string[]]$Arguments,$Seconds)
 if($Tool -ceq 'ssh-add.exe'){return [pscustomobject]@{ExitCode=if('__CASE__' -ceq 'signFailure'){1}else{0}}}
 if($Tool -cne 'ssh.exe' -or $Arguments -notcontains 'BatchMode=yes' -or $Arguments -notcontains 'StrictHostKeyChecking=yes' -or $Arguments -notcontains 'ClearAllForwardings=yes'){throw 'UNSAFE_SSH'}
 $nonce=$Arguments[-1].Split(' ')[1];if('__CASE__' -ceq 'wrongNonce'){$nonce='b'*32}
 [pscustomobject]@{ExitCode=0;StoppedByRunner=$false;Stdout="MB_CLOCK_V1|$nonce|1794839418599|yes";Stderr=''}
}
'@
 [IO.File]::WriteAllText((Join-Path $dir 'health.ps1'),$mock.Replace('__CASE__',$case))
 $tokenMock=@'
function Unprotect-HealthToken {param($Cipher) if('__CASE__' -ceq 'decryptFailure'){throw 'HEALTH_TOKEN_DECRYPT_FAILED'};'fixture-token-never-print'}
function Test-HealthTokenAuthority {param($Token) if('__CASE__' -ceq 'authFailure'){throw 'HEALTH_TOKEN_HTTP_FAILED'};'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'}
'@
 [IO.File]::WriteAllText((Join-Path $dir 'library.ps1'),$tokenMock.Replace('__CASE__',$case))
 [IO.File]::WriteAllBytes((Join-Path $dir 'health-token.dpapi'),[byte[]]::new(200))
 $result=Join-Path $dir 'result.json';$worker=Join-Path $dir 'worker.ps1'
 $withCollector=$case -cin @('collectorSuccess','collectorFailure','collectorException')
 $withToken=$case -cin @('tokenSuccess','decryptFailure','authFailure','collectorSuccess','collectorFailure','collectorException')
 $source=(New-HealthScheduledWorkerSource $run -WithToken:$withToken -WithCollector:$withCollector).Replace('C:\ProgramData\MarketBrainPaytmHealth\key-custody',$dir).Replace('C:\ProgramData\MarketBrainPaytmHealth\token-custody',$dir).Replace($c.result,$result)
 if($withCollector){
  $stub=@'
function Start-Sleep {param($Seconds)}
function Invoke-CollectorCycle {param($Token,$SshArguments,$Boot,[switch]$Revoke)
 if(-not $Revoke -and '__CASE__' -ceq 'collectorException'){throw 'COLLECTOR_FIXTURE_FAILURE'}
 [pscustomobject]@{accepted=(-not $Revoke -and '__CASE__' -ceq 'collectorSuccess');healthySubmitted=(-not $Revoke);revoked=[bool]$Revoke}
}
'@
  $source=$source.Replace(" `$r.stage='COLLECTOR'",($stub.Replace('__CASE__',$case)+"`r`n `$r.stage='COLLECTOR'"))
 }
 [IO.File]::WriteAllText($worker,$source)
 & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $worker
 $exit=$LASTEXITCODE;$report=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
 if($case -cin @('success','tokenSuccess','collectorSuccess')){if($exit -ne 0){throw 'WORKER_SUCCESS_FAILED'};Assert-HealthScheduledWorker $report $run;if($withToken){Assert-HealthScheduledTokenResult $report}}
 else{$caught=$false;try{Assert-HealthScheduledWorker $report $run}catch{$caught=$true};if($exit -eq 0 -or -not $caught -or -not $report.failure){throw "WORKER_FAILURE_ACCEPTED_$case"}}
 if($withCollector -and (-not $report.finalHealthRevoked -or -not $report.applicationLocked)){throw 'COLLECTOR_REVOCATION_MISSING'}
 $count++
 if(([IO.File]::ReadAllText($result)).Contains('fixture-token-never-print')){throw 'TOKEN_IN_REPORT'}
}
foreach($bad in @([pscustomobject]@{tokenDecrypted=$false;tokenAuthenticated=$true;applicationLocked=$true;applicationBootId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},[pscustomobject]@{tokenDecrypted=$true;tokenAuthenticated='true';applicationLocked=$true;applicationBootId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},[pscustomobject]@{tokenDecrypted=$true;tokenAuthenticated=$true;applicationLocked=$true;applicationBootId='wrong'})){
 $caught=$false;try{Assert-HealthScheduledTokenResult $bad}catch{$caught=$true};if(-not $caught){throw 'TOKEN_INVALID_PROOF_ACCEPTED'};$count++
}
$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaytmHealthScheduledAccess.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw $errors};$count++
Write-Host "$count health scheduled checks passed; native PS5.1 fixture workers, no real scheduler/account/policy/network changes."
