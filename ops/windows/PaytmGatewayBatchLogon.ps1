#Requires -Version 7.0
# Local LSA API: only the reviewed account's batch-logon allow right can be added.
function Initialize-PaytmBatchPolicyApi {
 if('MarketBrainBatchPolicyV1' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class MarketBrainBatchPolicyV1 {
 [StructLayout(LayoutKind.Sequential)] struct U { public ushort Length, MaximumLength; public IntPtr Buffer; }
 [StructLayout(LayoutKind.Sequential)] struct O { public int Length; public IntPtr RootDirectory,ObjectName; public uint Attributes; public IntPtr SecurityDescriptor,SecurityQualityOfService; }
 [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system,ref O attributes,uint access,out IntPtr handle);
 [DllImport("advapi32.dll")] static extern uint LsaEnumerateAccountsWithUserRight(IntPtr handle,ref U right,out IntPtr buffer,out uint count);
 [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr handle,byte[] sid,ref U right,uint count);
 [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr buffer);
 [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr handle);
 [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);
 static void Check(uint status) { if(status!=0) throw new Win32Exception((int)LsaNtStatusToWinError(status)); }
 static IntPtr Open(uint access) { O a=new O();a.Length=Marshal.SizeOf(typeof(O));IntPtr h;Check(LsaOpenPolicy(IntPtr.Zero,ref a,access,out h));return h; }
 static U Text(string s) { U u=new U();u.Buffer=Marshal.StringToHGlobalUni(s);u.Length=(ushort)(s.Length*2);u.MaximumLength=(ushort)(u.Length+2);return u; }
 public static string[] Read(bool deny) {
  IntPtr h=Open(0x801),b=IntPtr.Zero;U right=Text(deny?"SeDenyBatchLogonRight":"SeBatchLogonRight");
  try {
   uint n;uint status=LsaEnumerateAccountsWithUserRight(h,ref right,out b,out n);
   if(status==0x8000001A) return new string[0]; // STATUS_NO_MORE_ENTRIES, not access denied
   Check(status);if(n>512) throw new InvalidOperationException("SCHEDULE_POLICY_SIZE");
   string[] result=new string[n];
   for(int i=0;i<n;i++) result[i]=new SecurityIdentifier(Marshal.ReadIntPtr(b,i*IntPtr.Size)).Value;
   Array.Sort(result,StringComparer.Ordinal);return result;
  } finally {if(b!=IntPtr.Zero)LsaFreeMemory(b);Marshal.FreeHGlobal(right.Buffer);LsaClose(h);}
 }
 public static void Grant(string sid) {
  if(sid!="S-1-5-21-3041730714-102984520-3202743044-1010") throw new InvalidOperationException("SCHEDULE_POLICY_SID");
  SecurityIdentifier s=new SecurityIdentifier(sid);byte[] bytes=new byte[s.BinaryLength];s.GetBinaryForm(bytes,0);
  IntPtr h=Open(0x810);U right=Text("SeBatchLogonRight");
  try {Check(LsaAddAccountRights(h,bytes,ref right,1));} finally {Marshal.FreeHGlobal(right.Buffer);LsaClose(h);}
 }
}
'@
}
function Get-PaytmBatchPolicy {
 Initialize-PaytmBatchPolicyApi
 [pscustomobject]@{allow=@([MarketBrainBatchPolicyV1]::Read($false));deny=@([MarketBrainBatchPolicyV1]::Read($true))}
}
function Add-PaytmBatchRight {
 Initialize-PaytmBatchPolicyApi
 [MarketBrainBatchPolicyV1]::Grant((Get-PaytmKeyContract).accountSid)
}
function Assert-PaytmBatchPolicy($Policy) {
 $sid=(Get-PaytmKeyContract).accountSid;$guest=$sid.Substring(0,$sid.LastIndexOf('-'))+'-501'
 foreach($name in @('allow','deny')){
  if($null -eq $Policy.$name -or @($Policy.$name).Count -gt 512){throw 'SCHEDULE_POLICY_INVALID'}
  foreach($value in $Policy.$name){if($value -cnotmatch '^S-1-[0-9]+(-[0-9]+)+$'){throw 'SCHEDULE_POLICY_INVALID'}}
 }
 # Standalone machine and exact Users-only membership are checked before this.
 # Only known guest-only denials can be excluded confidently; preserve every other deny for review.
 if(@($Policy.deny|Where-Object {$_ -cnotin @('S-1-5-32-546',$guest)}).Count){throw 'SCHEDULE_BATCH_DENY_POLICY_REVIEW_REQUIRED'}
}
function Assert-PaytmBatchPolicyDelta($Before,$After) {
 Assert-PaytmBatchPolicy $After
 $expected=@(@($Before.allow)+@((Get-PaytmKeyContract).accountSid)|Sort-Object -Unique)
 if(($expected -join ',') -cne (@($After.allow|Sort-Object -Unique) -join ',') -or
    (@($Before.deny|Sort-Object -Unique) -join ',') -cne (@($After.deny|Sort-Object -Unique) -join ',')){
  throw 'SCHEDULE_POLICY_POSTCHECK_DRIFT'
 }
}
function Assert-PaytmReviewedBatchReceipt([string]$Path) {
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne 'F7E3EAEF6A5FCB175550939ECA86BB811C912DDEF8E52CDC7388B747D14CBAAB'){throw 'SCHEDULE_LAUNCH_RECEIPT_NOT_REVIEWED'}
 $r=Read-PaytmRepairJson $Path 65536
 if($r.runId -cne '8d26b08689d940ce8798fd4095b302c5' -or $r.status -cne 'SCHEDULED_PROBE_INVENTORY_CAPTURED' -or $r.failure -or @($r.existingProbes).Count -ne 1){throw 'SCHEDULE_LAUNCH_RECEIPT_INVALID'}
}
function Assert-PaytmBatchRecoveryTask {
 $oldRun='6b3bcee5eac24157aa38b858b96ae253';$c=Get-PaytmScheduledProbeContract $oldRun
 $tasks=@(Get-ScheduledTask -ErrorAction Stop|Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -clike 'MarketBrain-Gateway-Key-Probe-*'})
 if($tasks.Count -ne 1 -or $tasks[0].TaskName -cne $c.name -or [string]$tasks[0].State -cne 'Disabled'){throw 'SCHEDULE_RETAINED_TASK_DRIFT'}
 Assert-PaytmProbeTask $tasks[0] $oldRun $false
 if((Get-ScheduledTaskInfo -TaskName $c.name -TaskPath $c.path -ErrorAction Stop).LastTaskResult -ne 267011){throw 'SCHEDULE_RETAINED_TASK_ALREADY_RUN'}
 $null=Assert-PaytmAccountPath $c.result
 if(Test-Path -LiteralPath $c.result){throw 'SCHEDULE_RETAINED_RESULT_EXISTS'}
 $worker=Assert-PaytmAccountPath (Join-Path $c.directory 'worker.ps1')
 Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.directory) (Get-PaytmKeyContract).accountSid
 if((Get-FileHash -LiteralPath $worker).Hash -cne '20FA8182D54A78E41168DA5ABFAC9B9DFC8AC85670DB39ED252315E3A11D0A0C'){throw 'SCHEDULE_RETAINED_WORKER_CHANGED'}
}
function Invoke-PaytmBatchRecovery($Report,[scriptblock]$Checkpoint,[string]$CustodyReportPath,[string]$LaunchReportPath) {
 $oldRun='6b3bcee5eac24157aa38b858b96ae253';$c=Get-PaytmScheduledProbeContract $oldRun;$taskTouched=$false
 try {
  $Report.stage='REVALIDATE'; &$Checkpoint
  Assert-PaytmReviewedBatchReceipt $LaunchReportPath
  $Report.prerequisites=Assert-PaytmScheduledPrerequisites $CustodyReportPath
  $machine=@(Get-CimInstance -ClassName Win32_ComputerSystem -Property PartOfDomain -ErrorAction Stop)
  if($machine.Count -ne 1 -or $machine[0].PartOfDomain -ne $false){throw 'SCHEDULE_DOMAIN_POLICY_REVIEW_REQUIRED'}
  Assert-PaytmBatchRecoveryTask
  $Report.policyBefore=Get-PaytmBatchPolicy;Assert-PaytmBatchPolicy $Report.policyBefore; &$Checkpoint
  $Report.stage='GRANT_ACCOUNT_BATCH_LOGON'; &$Checkpoint
  # Recheck account/task after policy capture, before the only policy mutation.
  $null=Assert-PaytmScheduledPrerequisites $CustodyReportPath;Assert-PaytmBatchRecoveryTask
  if((Get-PaytmKeyContract).accountSid -cnotin $Report.policyBefore.allow){
   $Report.grantAttempted=$true; &$Checkpoint;Add-PaytmBatchRight
  }
  $Report.policyAfter=Get-PaytmBatchPolicy;Assert-PaytmBatchPolicyDelta $Report.policyBefore $Report.policyAfter
  $Report.rightVerified=$true; &$Checkpoint
  $Report.stage='RUN_RETAINED_SIGNING_PROBE'; &$Checkpoint
  Assert-PaytmBatchRecoveryTask
  $taskTouched=$true
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
  $tasks=@(Get-PaytmProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
  Assert-PaytmProbeTask $tasks[0] $oldRun $true
  Start-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop;$Report.startRequested=$true; &$Checkpoint
  Wait-PaytmProbeTask $oldRun $Report $Checkpoint
  Assert-PaytmScheduledWorker $Report.worker $oldRun
  if($Report.lastTaskResult -ne 0){throw 'SCHEDULE_NONZERO_TASK_RESULT'}
  $Report.signingPassed=$true
 } finally {
  if($taskTouched){
   try{
    $tasks=@(Get-PaytmProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
    Assert-PaytmProbeTask $tasks[0] $oldRun ([bool]$tasks[0].Settings.Enabled)
    $null=Disable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
    $tasks=@(Get-PaytmProbeTask $c.name);Assert-PaytmProbeTask $tasks[0] $oldRun $false;$Report.taskDisabled=$true
    if([string]$tasks[0].State -cin @('Running','Queued')){
     Stop-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
     $clock=[Diagnostics.Stopwatch]::StartNew()
     do{$tasks=@(Get-PaytmProbeTask $c.name);if([string]$tasks[0].State -cnotin @('Running','Queued')){break};Start-Sleep -Milliseconds 250}while($clock.Elapsed.TotalSeconds -lt 5)
     if([string]$tasks[0].State -cin @('Running','Queued')){throw 'SCHEDULE_STOP_NOT_CONFIRMED'}
    }
    if($Report.signingPassed){
     Assert-PaytmProbeTask $tasks[0] $oldRun $false
     Unregister-ScheduledTask -TaskName $c.name -TaskPath $c.path -Confirm:$false -ErrorAction Stop
     if(@(Get-PaytmProbeTask $c.name).Count){throw 'SCHEDULE_REMOVE_NOT_CONFIRMED'};$Report.taskRemoved=$true
    }
   }catch{$Report.cleanupFailure='SCHEDULE_CLEANUP_REVIEW_REQUIRED'}
  }
  &$Checkpoint
 }
}
