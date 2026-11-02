#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1')){. (Join-Path $PSScriptRoot $name)}
$checks=0
function Check($Value,$Name){if(-not $Value){throw "BATCH_TEST_FAILED $Name"};$script:checks++}
function Reject($Action,$Name){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad $Name}
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
# Portable dev PS7 lacks reference assemblies. Compile the actual C# in Windows PS5,
# then load the DLL here. Compilation does not invoke LSA or change policy.
$text=Get-Content -Raw (Join-Path $PSScriptRoot 'PaytmGatewayBatchLogon.ps1')
$cs=[regex]::Match($text,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
$dll=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-batch-interop-'+[guid]::NewGuid().ToString('N')+'.dll')
$compile="`$ErrorActionPreference='Stop';Add-Type -TypeDefinition ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cs))+"'))) -OutputAssembly '"+$dll.Replace("'","''")+"'"
$handle=Start-TunnelProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($compile)))
$built=Complete-TunnelProcess $handle -LimitSeconds 30
Check ($built.ExitCode -eq 0 -and -not $built.StoppedByRunner) ('native interop compilation: '+$built.Stderr)
Add-Type -Path $dll
Initialize-PaytmBatchPolicyApi
Check ($null -ne ('MarketBrainBatchPolicyV1' -as [type])) 'actual LSA PInvoke source compiles without policy access'
Reject {[MarketBrainBatchPolicyV1]::Grant('S-1-5-32-544')} 'native mutation boundary rejects any other SID before OS access'
$sid=(Get-PaytmKeyContract).accountSid
$otherSid=$sid.Substring(0,$sid.LastIndexOf('-'))+'-1003';$script:lookupMode='user'
function Get-LocalUser {param($SID,$ErrorAction)
 if($script:lookupMode -ceq 'denied' -or $script:case -ceq 'unresolvedDeny'){throw [UnauthorizedAccessException]::new()}
 if($script:lookupMode -ceq 'absent'){return}
 [pscustomobject]@{SID=[pscustomobject]@{Value=if($script:lookupMode -ceq 'wrongSid'){'S-1-5-21-1-2-3-1003'}else{$SID.Value}}}
}
$assessment=@(Get-PaytmBatchDenyAssessment @($otherSid))
Check ($assessment.Count -eq 1 -and -not $assessment[0].blocksRepair -and $assessment[0].classification -ceq 'UNRELATED_LOCAL_USER') 'reported RID1003 resolved as unrelated local user, not ignored by RID alone'
foreach($mode in @('absent','denied','wrongSid')){
 $script:lookupMode=$mode;Check (@(Get-PaytmBatchDenyAssessment @($otherSid))[0].blocksRepair) ('unresolved identity blocks '+$mode)
}
$script:lookupMode='user'
$differentUserPolicy=[pscustomobject]@{allow=@('S-1-5-32-544');deny=@($otherSid)}
Assert-PaytmBatchPolicyDelta $differentUserPolicy ([pscustomobject]@{allow=@('S-1-5-32-544',$sid);deny=@($otherSid)})
Check $true 'unrelated user deny preserved during scoped grant'
$before=[pscustomobject]@{allow=@('S-1-5-32-544');deny=@('S-1-5-32-546')}
Assert-PaytmBatchPolicy $before;Check $true 'guest-only deny allowed with standalone Users-only preconditions'
$after=[pscustomobject]@{allow=@('S-1-5-32-544',$sid);deny=@('S-1-5-32-546')}
Assert-PaytmBatchPolicyDelta $before $after;Check $true 'only reviewed SID added'
foreach($deny in @($sid,'S-1-1-0','S-1-5-32-545','S-1-5-11','S-1-5-113','S-1-5-3','S-1-5-21-1-2-3-999')){
 Reject {Assert-PaytmBatchPolicy ([pscustomobject]@{allow=@();deny=@($deny)})} ('deny policy preserved '+$deny)
}
Reject {Assert-PaytmBatchPolicyDelta $before ([pscustomobject]@{allow=@($sid);deny=$before.deny})} 'other grantee removal blocked'
Reject {Assert-PaytmBatchPolicyDelta $before ([pscustomobject]@{allow=@($sid,'S-1-1-0','S-1-5-32-544');deny=$before.deny})} 'other grantee addition blocked'
Reject {Assert-PaytmBatchPolicyDelta $before ([pscustomobject]@{allow=$after.allow;deny=@()})} 'deny policy removal blocked'
# Retain real validators for direct drift fixtures; recovery OS operations below are mocked.
$realTaskCheck=(Get-Item Function:Assert-PaytmBatchRecoveryTask).ScriptBlock
$realReceiptCheck=(Get-Item Function:Assert-PaytmReviewedBatchReceipt).ScriptBlock
function Assert-PaytmReviewedBatchReceipt($Path){if($script:case -ceq 'receipt'){throw 'SCHEDULE_LAUNCH_RECEIPT_NOT_REVIEWED'}}
function Assert-PaytmScheduledPrerequisites($Path){if($script:case -ceq 'custody'){throw 'SCHEDULE_CUSTODY_STATE_DRIFT'};[pscustomobject]@{sid=$sid}}
function Get-CimInstance {param($ClassName,$Property,$ErrorAction) [pscustomobject]@{PartOfDomain=($script:case -ceq 'domain')}}
function Assert-PaytmBatchRecoveryTask {if($script:case -ceq 'taskDrift'){throw 'SCHEDULE_RETAINED_TASK_DRIFT'}}
function Get-PaytmBatchPolicy {
 if($script:case -ceq 'readDenied'){throw [ComponentModel.Win32Exception]::new(5)}
 $allow=@('S-1-5-32-544');if($script:grants -or $script:case -ceq 'alreadyGranted'){$allow+=@($sid)}
 if($script:case -ceq 'postDrift' -and $script:grants){$allow+=@('S-1-1-0')}
 [pscustomobject]@{allow=$allow;deny=if($script:case -ceq 'deny'){@($sid)}elseif($script:case -cin @('otherUserDeny','unresolvedDeny')){@($otherSid)}else{@('S-1-5-32-546')}}
}
function Add-PaytmBatchRight {$script:grants++;if($script:case -ceq 'grantDenied'){throw [ComponentModel.Win32Exception]::new(5)}}
function Enable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:enables++;$script:task.Settings.Enabled=$true;$script:task.State='Ready';if($script:case -ceq 'enableThrows'){throw 'SCHEDULE_ENABLE_FAILED'}}
function Get-PaytmProbeTask($Name){if($script:removed){return};$script:task}
function Assert-PaytmProbeTask($Task,$RunId,$Enabled){if($script:case -ceq 'cleanupDrift' -and $script:starts){throw 'SCHEDULE_TASK_ACTION_DRIFT'};if($Task.Settings.Enabled -ne $Enabled){throw 'SCHEDULE_TASK_SETTINGS_DRIFT'}}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++;if($script:case -ceq 'startThrows'){throw 'SCHEDULE_START_FAILED'};$script:task.State='Running'}
function Wait-PaytmProbeTask($RunId,$Report,$Checkpoint){
 if($script:case -ceq 'timeout'){throw 'SCHEDULE_TASK_TIMEOUT'}
 $Report.worker=[pscustomobject]@{runId=$RunId};$Report.lastTaskResult=if($script:case -ceq 'nonzero'){1}else{0};$script:task.State='Ready'
}
function Assert-PaytmScheduledWorker($Worker,$RunId){if($script:case -ceq 'workerFailed'){throw 'SCHEDULE_WORKER_NOT_PASSED'}}
function Disable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:disables++;$script:task.Settings.Enabled=$false;if($script:task.State -cne 'Running'){$script:task.State='Disabled'}}
function Stop-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:stops++;$script:task.State='Disabled'}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,$Confirm,$ErrorAction) $script:removes++;if($script:case -ceq 'removeFailed'){throw 'SCHEDULE_REMOVE_FAILED'};$script:removed=$true}
$cases=@('pass','alreadyGranted','otherUserDeny','unresolvedDeny','receipt','custody','domain','taskDrift','deny','readDenied','grantDenied','postDrift','enableThrows','startThrows','timeout','workerFailed','nonzero','cleanupDrift','removeFailed')
foreach($case in $cases){
 $script:case=$case;$script:grants=0;$script:enables=0;$script:starts=0;$script:disables=0;$script:stops=0;$script:removes=0;$script:removed=$false
 $script:task=[pscustomobject]@{Settings=[pscustomobject]@{Enabled=$false};State='Disabled'}
 $report=[ordered]@{stage='';policyBefore=$null;policyAfter=$null;grantAttempted=$false;rightVerified=$false;startRequested=$false;signingPassed=$false;taskDisabled=$false;taskRemoved=$false;cleanupFailure=$null;worker=$null;lastTaskResult=$null}
 $failed=$false;try{Invoke-PaytmBatchRecovery $report {} 'custody' 'launch'}catch{$failed=$true}
 if($case -cin @('pass','alreadyGranted','otherUserDeny')){
  Check (-not $failed -and $report.signingPassed -and $report.taskRemoved -and $script:starts -eq 1 -and $script:disables -eq 1) ('one run and exact successful cleanup '+$case)
  Check ($script:grants -eq $(if($case -ceq 'alreadyGranted'){0}else{1})) ('grant idempotency '+$case)
 }else{Check ($failed -or $report.cleanupFailure) ('failure surfaced '+$case)}
 if($case -cin @('receipt','custody','domain','taskDrift','deny','readDenied','unresolvedDeny')){Check ($script:grants -eq 0 -and $script:enables -eq 0) ('no mutation on preflight '+$case)}
 if($case -ceq 'otherUserDeny'){Check ($report.denyAssessment[0].classification -ceq 'UNRELATED_LOCAL_USER' -and @($report.policyAfter.deny)[0] -ceq $otherSid) 'complete workflow records identity decision and unchanged deny'}
 if($case -cin @('grantDenied','postDrift')){Check ($report.grantAttempted -and $script:enables -eq 0) ('partial policy evidence before launch '+$case)}
 if($case -cin @('enableThrows','startThrows','timeout','workerFailed','nonzero')){Check ($script:disables -eq 1 -and -not $script:removed -and $report.taskDisabled) ('failed task disabled retained '+$case)}
 if($case -ceq 'timeout'){Check ($script:stops -eq 1) 'running timeout stopped'}
 if($case -ceq 'cleanupDrift'){Check ($script:disables -eq 0 -and $script:removes -eq 0 -and $report.cleanupFailure) 'unowned drift never changed'}
 if($case -ceq 'removeFailed'){Check ($report.signingPassed -and $report.cleanupFailure -and -not $report.taskRemoved) 'cleanup failure not overall acceptance'}
}
# Actual reviewed-task validator with mocked filesystem/OS metadata, no task changes.
function Assert-PaytmProbeTask($Task,$RunId,$Enabled){if($script:binding -ceq 'definition'){throw 'SCHEDULE_TASK_ACTION_DRIFT'}}
function Get-ScheduledTask {param($ErrorAction)
 $v=[pscustomobject]@{TaskName='MarketBrain-Gateway-Key-Probe-6b3bcee5eac24157aa38b858b96ae253';TaskPath='\';State='Disabled'}
 if($script:binding -ceq 'name'){$v.TaskName='MarketBrain-Gateway-Key-Probe-other'}
 if($script:binding -ceq 'running'){$v.State='Running'}
 $v;if($script:binding -ceq 'multiple'){$v}
}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) [pscustomobject]@{LastTaskResult=if($script:binding -ceq 'ran'){0}else{267011}}}
function Test-Path {param($LiteralPath) $script:binding -ceq 'result'}
function Assert-PaytmAccountPath($Path){$Path}
function Get-Acl {param($LiteralPath) [pscustomobject]@{}}
function Assert-PaytmAccountAcl($Acl,$Sid){if($script:binding -ceq 'acl'){throw 'ACCOUNT_ACL_RIGHTS'}}
function Get-FileHash {param($LiteralPath) [pscustomobject]@{Hash=if($script:binding -ceq 'worker'){'wrong'}else{'20FA8182D54A78E41168DA5ABFAC9B9DFC8AC85670DB39ED252315E3A11D0A0C'}}}
$script:binding='pass';&$realTaskCheck;Check $true 'actual retained-task binding accepts reviewed identity'
foreach($binding in @('name','running','multiple','ran','result','acl','worker','definition')){$script:binding=$binding;Reject {&$realTaskCheck} ('actual retained-task guard '+$binding)}
Reject {&$realReceiptCheck 'unreviewed.json'} 'receipt digest mismatch blocked'
foreach($file in @('PaytmGatewayBatchLogon.ps1','RepairPaytmGatewayScheduledSigning.ps1','TestPaytmGatewayBatchLogon.ps1')){
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) ('parse '+$file)
}
# Execute the actual report launcher in an isolated fixture; all policy/task operations mocked.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-batch-launcher-'+[guid]::NewGuid().ToString('N'))
$scripts=Join-Path $temp 'scripts';$null=New-Item -ItemType Directory -Path $scripts -Force
foreach($file in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1','RepairPaytmGatewayScheduledSigning.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $scripts}
$mocks=@'
function Assert-PaytmCustodyController {}
function Import-Module {param($Name,$ErrorAction)}
function Get-PaytmReadinessProgress {@([pscustomobject]@{id='G2';percent=60})}
function Invoke-PaytmBatchRecovery($Report,$Checkpoint,$CustodyReportPath,$LaunchReportPath){
 $Report.stage='GRANT_ACCOUNT_BATCH_LOGON';$Report.grantAttempted=$true;&$Checkpoint
 if($global:launchCase -ceq 'nativeFailure'){throw [ComponentModel.Win32Exception]::new(1385,'PRIVATE_SENTINEL')}
 $Report.startRequested=$true;$Report.signingPassed=$true;$Report.rightVerified=$true
 if($global:launchCase -ceq 'cleanupFailure'){$Report.cleanupFailure='SCHEDULE_CLEANUP_REVIEW_REQUIRED'}else{$Report.taskRemoved=$true}
}
'@
[IO.File]::AppendAllText((Join-Path $scripts 'PaytmGatewayBatchLogon.ps1'),("`n"+$mocks))
foreach($mode in @('success','nativeFailure','cleanupFailure')){
 $global:launchCase=$mode;$output=Join-Path $temp $mode;$failed=$false;$console=@()
 try{$console=@(& (Join-Path $scripts 'RepairPaytmGatewayScheduledSigning.ps1') -OutputDirectory $output 6>&1)}catch{$failed=$true}
 $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) ('one launcher report '+$mode)
 $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
 Check ($raw -notmatch 'PRIVATE_SENTINEL' -and -not $r.keyImported -and -not $r.passwordChanged -and -not $r.ordersEnabled) ('secret exclusion and authority flags '+$mode)
 if($mode -ceq 'success'){Check (-not $failed -and $r.status -ceq 'BATCH_LOGON_AND_SIGNING_PASSED_SUPERVISOR_PENDING' -and $r.taskRemoved) 'launcher accepts exact completion'}
 elseif($mode -ceq 'nativeFailure'){Check ($failed -and $r.status -ceq 'REVIEW_REQUIRED' -and $r.failureDetails.nativeErrorCode -eq 1385 -and $r.grantAttempted) 'launcher preserves native code and partial mutation intent'}
 else{Check ($failed -and $r.status -ceq 'REVIEW_REQUIRED' -and $r.cleanupFailure) 'launcher cleanup failure blocks acceptance'}
}
Write-Host "PASS: $checks batch-policy assertions; $($cases.Count) mocked recovery workflows and 3 launcher workflows. Native interop compiled; no local policy/task/key/credential/network mutations."
