#Requires -Version 7.0
# Local LSA API: only the reviewed account's batch-logon allow right can be added.
function Initialize-HealthBatchPolicyApi {
 if('MarketBrainHealthBatchPolicyV1' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class MarketBrainHealthBatchPolicyV1 {
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
  if(sid!="S-1-5-21-3041730714-102984520-3202743044-1011") throw new InvalidOperationException("SCHEDULE_POLICY_SID");
  SecurityIdentifier s=new SecurityIdentifier(sid);byte[] bytes=new byte[s.BinaryLength];s.GetBinaryForm(bytes,0);
  IntPtr h=Open(0x810);U right=Text("SeBatchLogonRight");
  try {Check(LsaAddAccountRights(h,bytes,ref right,1));} finally {Marshal.FreeHGlobal(right.Buffer);LsaClose(h);}
 }
}
'@
}
function Get-HealthBatchPolicy {
 Initialize-HealthBatchPolicyApi
 [pscustomobject]@{allow=@([MarketBrainHealthBatchPolicyV1]::Read($false));deny=@([MarketBrainHealthBatchPolicyV1]::Read($true))}
}
function Add-HealthBatchRight {
 Initialize-HealthBatchPolicyApi
 [MarketBrainHealthBatchPolicyV1]::Grant((Get-HealthScheduledKeyContract).accountSid)
}
function Get-HealthBatchDenyAssessment([string[]]$DeniedSids) {
 $sid=(Get-HealthScheduledKeyContract).accountSid;$machineSid=$sid.Substring(0,$sid.LastIndexOf('-'));$guest=$machineSid+'-501'
 foreach($denied in $DeniedSids){
  $entry=[ordered]@{sid=$denied;classification='UNRESOLVED_OR_GROUP';blocksRepair=$true}
  if($denied -ceq $sid){$entry.classification='HEALTH_ACCOUNT'}
  elseif($denied -cin @('S-1-5-32-546',$guest)){
   # Exact Users-only membership is required by custody preflight.
   $entry.classification='GUEST_ONLY';$entry.blocksRepair=$false
  }elseif($denied -cmatch ('^'+[regex]::Escape($machineSid)+'-[0-9]+$')){
   try{
    # Resolve a local USER, not an arbitrary principal/group or just a different RID.
    $users=@(Get-LocalUser -SID ([Security.Principal.SecurityIdentifier]::new($denied)) -ErrorAction Stop)
    if($users.Count -eq 1 -and $users[0].SID.Value -ceq $denied){
     $entry.classification='UNRELATED_LOCAL_USER';$entry.blocksRepair=$false
    }
   }catch{$entry.classification='IDENTITY_LOOKUP_FAILED'}
  }
  [pscustomobject]$entry
 }
}
function Assert-HealthBatchPolicy($Policy,$Evidence=$null) {
 foreach($name in @('allow','deny')){
  if($null -eq $Policy.$name -or @($Policy.$name).Count -gt 512){throw 'SCHEDULE_POLICY_INVALID'}
  foreach($value in $Policy.$name){if($value -cnotmatch '^S-1-[0-9]+(-[0-9]+)+$'){throw 'SCHEDULE_POLICY_INVALID'}}
 }
 # A deny for a different verified local USER cannot be inherited by the gateway.
 # Group, gateway and unresolved denials still stop; no deny rule is removed.
 $assessment=@(Get-HealthBatchDenyAssessment @($Policy.deny))
 if($null -ne $Evidence){$Evidence.denyAssessment=$assessment}
 if(@($assessment|Where-Object {$_.blocksRepair}).Count){throw 'SCHEDULE_BATCH_DENY_POLICY_REVIEW_REQUIRED'}
}
function Assert-HealthBatchPolicyDelta($Before,$After) {
 Assert-HealthBatchPolicy $After
 $expected=@(@($Before.allow)+@((Get-HealthScheduledKeyContract).accountSid)|Sort-Object -Unique)
 if(($expected -join ',') -cne (@($After.allow|Sort-Object -Unique) -join ',') -or
    (@($Before.deny|Sort-Object -Unique) -join ',') -cne (@($After.deny|Sort-Object -Unique) -join ',')){
  throw 'SCHEDULE_POLICY_POSTCHECK_DRIFT'
 }
}
