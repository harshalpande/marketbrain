#Requires -Version 7.0
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmHealthAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmHealthKeyCustody.ps1','PaytmHealthScheduledProbe.ps1','PaytmHealthScheduledToken.ps1','PaytmTimeObservation.ps1','PaytmTimeAccountProbe.ps1','PaytmDurableCollector.ps1','PaytmDurableCollectorSetup.ps1')){. (Join-Path $PSScriptRoot $name)}
$run=[guid]::NewGuid().ToString('N');$d=Get-DurableCollectorDefinition ('0'*64);$password=$null;$attempted=$false
$reportRoot='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
Assert-TimeObservationAcl $reportRoot
$r=@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;taskRegistered=$false;disabledVerified=$false;workerStarted=$false;ordersEnabled=$false;sourceHashes=@{}}
function Save-InstallReport {
 $path=Join-Path $reportRoot 'collector-install-result.json';if(Test-Path -LiteralPath $path){Assert-TimeObservationAcl $path}
 $temp=Join-Path $reportRoot ('install-'+[guid]::NewGuid().ToString('N')+'.new')
 [IO.File]::WriteAllText($temp,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $temp
 if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
try{
 Save-InstallReport;Write-Host '[10%] Verify accepted runtime evidence and existing account/key/token custody.'
 $evidence='C:\MarketBrainData\Review\paytm-health-scheduled-e514d3f3a91d4e719ad31fadf66597df.json'
 if((Get-FileHash -LiteralPath $evidence).Hash -cne 'E67BF9258CDBD488A296D8E25FA61E142862068413172BDB765E465A142E89AA'){throw 'COLLECTOR_ACCEPTED_EVIDENCE_MISMATCH'}
 $null=Assert-HealthScheduledPrerequisites 'C:\MarketBrainData\Review\paytm-health-key-custody-d5e799ea1ba84d438008f64c13e41571.json'
 Assert-HealthScheduledTokenPrerequisites 'C:\MarketBrainData\Review\paytm-health-token-88ebf8fdc3de4c158351e86df95e7217.json'
 $null=Read-TimeObservation
 if((Test-Path -LiteralPath $d.root) -or (Test-Path -LiteralPath $d.work) -or @(Get-ScheduledTask|Where-Object {$_.TaskName -ceq $d.name -and $_.TaskPath -ceq '\'}).Count){throw 'COLLECTOR_INSTALL_COLLISION'}
 $source=New-DurableCollectorSource $run
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
 if($errors.Count -or $source.Contains('__RUN__') -or $source.Contains('__WORK__') -or $source.Contains('__RESULT__')){throw 'COLLECTOR_GENERATED_SOURCE'}
 Write-Host '[25%] Stage disabled startup task. Enter the existing Windows health-account password locally.'
 $password=Read-Host 'marketbrain-health Windows password' -AsSecureString
 $r.credentialCheck=Test-TimeAccountCredential $password
 if(-not $r.credentialCheck.accepted){throw 'COLLECTOR_WINDOWS_CREDENTIAL_REJECTED'}
 $r.stage='FILES';Save-InstallReport;Write-Progress -Activity 'Stage durable health collector' -PercentComplete 50 -Status 'Protected worker and stopped control'
 foreach($path in @($d.root,$d.work)){
  $null=New-Item -ItemType Directory -Path $path
  $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
  foreach($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-21-3041730714-102984520-3202743044-1011')){
   $rights=if($sid -eq 'S-1-5-21-3041730714-102984520-3202743044-1011'){if($path -ceq $d.work){'Modify'}else{'ReadAndExecute'}}else{'FullControl'}
   $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,'ContainerInherit,ObjectInherit','None','Allow'))
  }
  Set-Acl -LiteralPath $path -AclObject $acl
 }
 Assert-TimeObservationAcl $d.root
 $pins=ConvertFrom-PaytmHostPublicKey ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'paytm-vps-host-rsa.pub')).Trim())
 [IO.File]::WriteAllText((Join-Path $d.root 'worker.ps1'),$source,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $d.root 'known_hosts'),$pins.knownHost,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $d.root 'control.json'),(@{version=1;installationId=$run;enabled=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $d.work 'instance.lock'),'')
 $hash=(Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash;$d=Get-DurableCollectorDefinition $hash;$r.workerSha256=$hash
 foreach($name in @('worker.ps1','known_hosts','control.json')){Assert-TimeObservationAcl (Join-Path $d.root $name)}
 $r.knownHostsSha256=(Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash
 $r.stage='REGISTER_DISABLED';Save-InstallReport;Write-Host '[75%] Register disabled, non-admin startup task; no task start.'
 $action=New-ScheduledTaskAction -Execute $d.exe -Argument $d.arguments -WorkingDirectory $d.root
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-21-3041730714-102984520-3202743044-1011' -LogonType Password -RunLevel Limited
 $settings=New-ScheduledTaskSettingsSet -Disable -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 $definition=New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Description ('MarketBrain diagnostic collector '+$run)
 $plain=$null;$attempted=$true
 try{$plain=[Net.NetworkCredential]::new('', $password).Password;$null=Register-ScheduledTask -TaskName $d.name -TaskPath '\' -InputObject $definition -User ($env:COMPUTERNAME+'\marketbrain-health') -Password $plain}finally{$plain=$null}
 $r.taskRegistered=$true;Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
 $xml=[Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $d.name -TaskPath '\'));$sha=[Security.Cryptography.SHA256]::Create()
 try{$r.taskXmlSha256=([BitConverter]::ToString($sha.ComputeHash($xml))).Replace('-','')}finally{$sha.Dispose()}
 if(Read-DurableCollectorControl (Join-Path $d.root 'control.json') $run){throw 'COLLECTOR_CONTROL_ENABLED'}
 $r.disabledVerified=$true;$r.status='DURABLE_COLLECTOR_STAGED_DISABLED_ACTIVATION_PENDING';$r.stage='COMPLETE'
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'COLLECTOR_INSTALL_FAILED'};$r.failureLine=$_.InvocationInfo.ScriptLineNumber
 if($attempted){try{$t=Get-ScheduledTask -TaskName $d.name -TaskPath '\';if($t.Description -cne ('MarketBrain diagnostic collector '+$run)){throw 'COLLECTOR_TASK_OWNERSHIP'};$null=Disable-ScheduledTask -TaskName $d.name -TaskPath '\'}catch{$r.cleanupFailure='COLLECTOR_DISABLE_REVIEW_REQUIRED'}}
}finally{
 if($password){$password.Dispose()}
 foreach($name in @('InstallPaytmDurableCollector.ps1','PaytmDurableCollector.ps1','PaytmDurableCollectorSetup.ps1')){$r.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 Save-InstallReport;Write-Progress -Activity 'Stage durable health collector' -Completed;Write-Host ('[100%] '+$r.status);Write-Host 'Report saved for automatic collection.'
}
if($r.failure){throw ('Preserve staged files and task; do not rerun. '+$r.failure)}
