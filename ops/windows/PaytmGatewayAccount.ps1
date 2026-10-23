#Requires -Version 7.0
# Definitions only; the launcher owns consent. No private SSH keys are read or imported.
function Get-PaytmAccountContract {
    [pscustomobject]@{name='marketbrain-gateway';root='C:\ProgramData\MarketBrainPaytmGateway';
        description='MarketBrain gateway account';agentImage='C:\Windows\System32\OpenSSH\ssh-agent.exe'}
}
function Get-PaytmAgentControlAccess {
    # Read-only access check before account creation; elevation alone does not establish SCM rights.
    if(-not ('MarketBrainGatewayScmAccess' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MarketBrainGatewayScmAccess {
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenSCManager(string machine, string database, uint access);
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenService(IntPtr manager, string name, uint access);
 [DllImport("advapi32.dll", SetLastError=true)] static extern bool CloseServiceHandle(IntPtr handle);
 public static int Check() {
  IntPtr manager=OpenSCManager(null,null,1);
  if(manager==IntPtr.Zero) return Marshal.GetLastWin32Error();
  try {
   IntPtr service=OpenService(manager,"ssh-agent",0x17); // query config/status, change config, start
   if(service==IntPtr.Zero) return Marshal.GetLastWin32Error();
   CloseServiceHandle(service); return 0;
  } finally { CloseServiceHandle(manager); }
 }
}
'@
    }
    [MarketBrainGatewayScmAccess]::Check()
}
function Assert-PaytmAccountPath([string]$Path) {
    if(-not [IO.Path]::IsPathFullyQualified($Path)){throw 'ACCOUNT_ABSOLUTE_PATH_REQUIRED'}
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ACCOUNT_REPARSE_PATH_BLOCKED'}
        }
        $parent=[IO.Directory]::GetParent($cursor);$cursor=if($null -ne $parent){$parent.FullName}else{$null}
    }
    [IO.Path]::GetFullPath($Path)
}
function New-PaytmAccountAcl([string]$AccountSid,[switch]$Writable) {
    if($AccountSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'ACCOUNT_SID_INVALID'}
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach($sid in @('S-1-5-18','S-1-5-32-544',$AccountSid)){
        $rights=if($sid -ceq $AccountSid){if($Writable){'Modify'}else{'ReadAndExecute'}}else{'FullControl'}
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,'ContainerInherit,ObjectInherit','None','Allow'))
    }
    $acl
}
function Assert-PaytmAccountAcl($Acl,[string]$AccountSid,[switch]$Writable) {
    if(-not $Acl.AreAccessRulesProtected -or $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne 'S-1-5-32-544'){throw 'ACCOUNT_ACL_OWNER_OR_INHERITANCE'}
    $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if($rules.Count -ne 3){throw 'ACCOUNT_ACL_RULE_COUNT'}
    $seen=@{}
    foreach($rule in $rules){
        $sid=$rule.IdentityReference.Value
        if($seen.ContainsKey($sid) -or $sid -cnotin @('S-1-5-18','S-1-5-32-544',$AccountSid)){throw 'ACCOUNT_ACL_IDENTITY'}
        $seen[$sid]=$true
        $expected=[Security.AccessControl.FileSystemRights]::FullControl
        if($sid -ceq $AccountSid){$expected=if($Writable){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute}}
        # Windows may add Synchronize to an Allow ACE. Compare effective rights, not SDDL text/order.
        $withoutSync=([int]$rule.FileSystemRights -band (-bnot [int][Security.AccessControl.FileSystemRights]::Synchronize))
        $expectedWithoutSync=([int]$expected -band (-bnot [int][Security.AccessControl.FileSystemRights]::Synchronize))
        if($withoutSync -ne $expectedWithoutSync -or $rule.AccessControlType -ne 'Allow' -or $rule.IsInherited -or
           $rule.InheritanceFlags -ne 'ContainerInherit, ObjectInherit' -or $rule.PropagationFlags -ne 'None'){throw 'ACCOUNT_ACL_RIGHTS'}
    }
}
function Set-PaytmAccountDirectoryAcl([string]$Path,[string]$AccountSid,[switch]$Writable) {
    $null=Assert-PaytmAccountPath $Path
    $acl=New-PaytmAccountAcl $AccountSid -Writable:$Writable
    [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path),$acl)
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $Path) $AccountSid -Writable:$Writable
}
function Test-PaytmAccountPasswords([Security.SecureString]$First,[Security.SecureString]$Second) {
    if($null -eq $First -or $null -eq $Second -or $First.Length -lt 14 -or $First.Length -ne $Second.Length){return $false}
    $left=[IntPtr]::Zero;$right=[IntPtr]::Zero
    try{
        $left=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($First);$right=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
        $different=0
        for($i=0;$i -lt $First.Length;$i++){$different=$different -bor ([Runtime.InteropServices.Marshal]::ReadInt16($left,$i*2) -bxor [Runtime.InteropServices.Marshal]::ReadInt16($right,$i*2))}
        return $different -eq 0
    }finally{
        if($left -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($left)}
        if($right -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($right)}
    }
}
function Assert-PaytmAccountInventory($Inventory,[ValidateSet('Apply','Verify','Disable')][string]$Mode) {
    if(-not $Inventory.elevated -or -not $Inventory.native64Bit){throw 'ACCOUNT_ELEVATED_64BIT_REQUIRED'}
    if(-not $Inventory.toolsPresent){throw 'ACCOUNT_WINDOWS_CLIENT_TOOLS_MISSING'}
    $contract=Get-PaytmAccountContract
    if($Inventory.agentImage.Trim('"') -ine $contract.agentImage -or $Inventory.agentStartName -ine 'LocalSystem'){throw 'ACCOUNT_AGENT_SERVICE_IDENTITY_UNEXPECTED'}
    if($Mode -ceq 'Apply'){
        if($Inventory.agentControlError -ne 0){throw 'ACCOUNT_AGENT_SERVICE_CONTROL_DENIED'}
        if($Inventory.accountExists -or $Inventory.rootExists){throw 'ACCOUNT_TARGET_ALREADY_EXISTS_USE_VERIFY_OR_REVIEW'}
        if($Inventory.agentStatus -cne 'Stopped' -or $Inventory.agentStartType -cne 'Disabled'){throw 'ACCOUNT_AGENT_BASELINE_CHANGED'}
    }
    if($Mode -cne 'Disable' -and $Inventory.secondaryLogonStartType -ceq 'Disabled'){throw 'ACCOUNT_SECONDARY_LOGON_DISABLED_NO_POLICY_CHANGE'}
}
function Get-PaytmReadinessProgress {
    param([string]$Path=(Join-Path $PSScriptRoot '..\..\docs\paytm-readiness-progress.json'))
    $data=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    if($data.schemaVersion -ne 1 -or @($data.groups).Count -ne 6){throw 'ACCOUNT_PROGRESS_BASELINE_INVALID'}
    $ids=@{}
    foreach($group in $data.groups){
        if($group.id -cnotmatch '^G[1-6]$' -or $ids.ContainsKey($group.id) -or @($group.checkpoints).Count -ne 5){throw 'ACCOUNT_PROGRESS_GROUP_INVALID'}
        $ids[$group.id]=$true;$checkpointIds=@{};$accepted=0
        foreach($checkpoint in $group.checkpoints){
            if($checkpoint.id -cnotmatch ('^'+$group.id+'\.[1-5]$') -or $checkpointIds.ContainsKey($checkpoint.id)){throw 'ACCOUNT_PROGRESS_CHECKPOINT_INVALID'}
            $checkpointIds[$checkpoint.id]=$true
            if($null -ne $checkpoint.evidence){if($checkpoint.evidence -cnotmatch '^E\d+$'){throw 'ACCOUNT_PROGRESS_EVIDENCE_INVALID'};$accepted++}
        }
        [pscustomobject]@{id=$group.id;name=$group.name;acceptedCheckpoints=$accepted;totalCheckpoints=5;percent=($accepted*20);baselineDate=$data.baselineDate}
    }
}
function Write-PaytmAccountNewJson([string]$Path,$Value) {
    $null=Assert-PaytmAccountPath $Path
    $stream=[IO.File]::Open($Path,'CreateNew','Write','None')
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Read-PaytmOwnedAccount {
    $c=Get-PaytmAccountContract;$root=Assert-PaytmAccountPath $c.root
    $manifest=Join-Path $root 'installation.json';$null=Assert-PaytmAccountPath $manifest
    $file=Get-Item -LiteralPath $manifest -ErrorAction Stop
    if($file.Length -gt 8192){throw 'ACCOUNT_MANIFEST_SIZE'}
    $saved=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    if($saved.version -ne 1 -or $saved.name -cne $c.name -or $saved.root -cne $c.root -or $saved.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'ACCOUNT_MANIFEST_INVALID'}
    $account=Get-LocalUser -Name $c.name -ErrorAction Stop
    if($account.SID.Value -cne $saved.sid -or $account.Description -cne $c.description){throw 'ACCOUNT_OWNERSHIP_MISMATCH'}
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $root) $saved.sid
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath (Join-Path $root 'work')) $saved.sid -Writable
    # Account membership is checked by SID; never rely on localized group names.
    $groups=@(Get-PaytmLocalMembershipSnapshot | Where-Object {$saved.sid -cin $_.memberSids})
    if($groups.Count -ne 1 -or $groups[0].groupSid -cne 'S-1-5-32-545'){throw 'ACCOUNT_UNEXPECTED_GROUP_MEMBERSHIP'}
    $saved
}
function Get-PaytmLocalMembershipSnapshot {
    # Preflight also runs this before changes: unresolved old group members cannot cause a late surprise.
    foreach($group in @(Get-LocalGroup -ErrorAction Stop)){
        [pscustomobject]@{groupSid=$group.SID.Value;memberSids=@(Get-LocalGroupMember -SID $group.SID -ErrorAction Stop | ForEach-Object {$_.SID.Value})}
    }
}
function New-PaytmAccountProbeSource([string]$Sid,[string]$RunId) {
    if($Sid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or $RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'ACCOUNT_PROBE_BINDING_INVALID'}
    # Compatible with built-in Windows PowerShell 5.1: no per-user PowerShell 7 installation dependency.
    $template=@'
$ErrorActionPreference='Stop'
$probe=[ordered]@{version=1;runId='__RUN__';sidMatched=$false;nonAdmin=$false;protectedWriteDenied=$false;workWriteReadDelete=$false;agentEmpty=$false;agentExit=$null;failure=$null}
$process=$null;$probeFile=$null;$probeOwned=$false;$started=$false
try{
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $probe.sidMatched=$identity.User.Value -ceq '__SID__'
    $probe.nonAdmin=-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not ($probe.sidMatched -and $probe.nonAdmin)){throw 'IDENTITY'}
    try{$f=[IO.File]::Open('C:\ProgramData\MarketBrainPaytmGateway\installation.json','Open','Write','None');$f.Dispose()}catch [UnauthorizedAccessException]{$probe.protectedWriteDenied=$true}
    $probeFile='C:\ProgramData\MarketBrainPaytmGateway\work\probe-__RUN__.txt'
    $f=[IO.File]::Open($probeFile,'CreateNew','Write','None');$probeOwned=$true;try{$f.WriteByte(77)}finally{$f.Dispose()}
    $read=[IO.File]::ReadAllBytes($probeFile);[IO.File]::Delete($probeFile);$probeFile=$null;$probeOwned=$false
    $probe.workWriteReadDelete=$read.Length -eq 1 -and $read[0] -eq 77
    $info=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\OpenSSH\ssh-add.exe','-l')
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.RedirectStandardInput=$true
    $info.EnvironmentVariables.Remove('SSH_AUTH_SOCK');$info.EnvironmentVariables.Remove('SSH_AGENT_PID');$info.EnvironmentVariables.Remove('SSH_ASKPASS')
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(-not $process.Start()){throw 'AGENT_QUERY_START'};$started=$true
    $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync();$process.StandardInput.Close()
    if(-not $process.WaitForExit(10000)){throw 'AGENT_QUERY_TIMEOUT'}
    if(-not $out.Wait(2000) -or -not $err.Wait(2000)){throw 'AGENT_QUERY_OUTPUT'}
    $probe.agentExit=$process.ExitCode
    # No raw key list is emitted or written, even if unexpected identities exist.
    $probe.agentEmpty=$process.ExitCode -eq 1 -and (($out.Result+$err.Result).Trim() -ceq 'The agent has no identities.')
}catch{$probe.failure='ACCOUNT_PROBE_CHECK_FAILED'}finally{
    if($null -ne $process){if($started -and -not $process.HasExited){$process.Kill();[void]$process.WaitForExit(5000)};$process.Dispose()}
    if($probeOwned -and $null -ne $probeFile -and [IO.File]::Exists($probeFile)){[IO.File]::Delete($probeFile)}
}
$probe|ConvertTo-Json -Compress
'@
    $template.Replace('__SID__',$Sid).Replace('__RUN__',$RunId)
}
function Assert-PaytmAccountProbe($Probe,[string]$RunId) {
    if($Probe.version -ne 1 -or $Probe.runId -cne $RunId -or $null -ne $Probe.failure -or $Probe.agentExit -ne 1){throw 'ACCOUNT_PROBE_FAILED'}
    foreach($field in @('sidMatched','nonAdmin','protectedWriteDenied','workWriteReadDelete','agentEmpty')){
        if($Probe.$field -isnot [bool] -or -not $Probe.$field){throw "ACCOUNT_PROBE_$($field.ToUpperInvariant())"}
    }
}
function Invoke-PaytmAccountProbe([string]$Sid,[string]$RunId,[Security.SecureString]$Password) {
    $source=New-PaytmAccountProbeSource $Sid $RunId
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
    $info=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+$encoded))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.LoadUserProfile=$true
    $info.UserName='marketbrain-gateway';$info.Domain=$env:COMPUTERNAME;$info.Password=$Password
    $info.WorkingDirectory='C:\ProgramData\MarketBrainPaytmGateway'
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.RedirectStandardInput=$true
    foreach($name in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$info.EnvironmentVariables.Remove($name)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info;$started=$false
    try{
        if(-not $process.Start()){throw 'ACCOUNT_PROBE_START_FAILED'};$started=$true
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync();$process.StandardInput.Close()
        if(-not $process.WaitForExit(60000)){throw 'ACCOUNT_PROBE_TIMEOUT'}
        if(-not $out.Wait(5000) -or -not $err.Wait(5000) -or $process.ExitCode -ne 0 -or $out.Result.Length -gt 4096){throw 'ACCOUNT_PROBE_OUTPUT_FAILED'}
        $probe=$out.Result.Trim()|ConvertFrom-Json
        Assert-PaytmAccountProbe $probe $RunId
        $probe
    }finally{
        if($started -and -not $process.HasExited){$process.Kill($true);if(-not $process.WaitForExit(5000)){throw 'ACCOUNT_PROBE_STOP_FAILED'}}
        $process.Dispose()
    }
}
