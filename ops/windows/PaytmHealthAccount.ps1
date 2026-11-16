# Definitions only. Reuses proven SID, ACL and bounded exact-account probe helpers.
function Get-PaytmHealthAccountContract {
 [pscustomobject]@{name='marketbrain-health';root='C:\ProgramData\MarketBrainPaytmHealth';description='MarketBrain health collector account'}
}
function Read-PaytmHealthAccount {
 $c=Get-PaytmHealthAccountContract
 $null=Assert-PaytmAccountPath $c.root
 $path=Join-Path $c.root 'installation.json';$null=Assert-PaytmAccountPath $path
 if((Get-Item -LiteralPath $path).Length -gt 8192){throw 'HEALTH_ACCOUNT_MANIFEST_SIZE'}
 $m=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 if($m.version -ne 1 -or $m.name -cne $c.name -or $m.root -cne $c.root -or $m.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'HEALTH_ACCOUNT_MANIFEST_INVALID'}
 $a=Get-LocalUser -Name $c.name -ErrorAction Stop
 if($a.SID.Value -cne $m.sid -or $a.Description -cne $c.description){throw 'HEALTH_ACCOUNT_OWNERSHIP_MISMATCH'}
 Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) $m.sid
 $work=Join-Path $c.root 'work';$null=Assert-PaytmAccountPath $work
 Assert-PaytmAccountAcl (Get-Acl -LiteralPath $work) $m.sid -Writable
 $groups=@(Get-PaytmLocalMembershipSnapshot|Where-Object {$m.sid -cin $_.memberSids})
 if($groups.Count -ne 1 -or $groups[0].groupSid -cne 'S-1-5-32-545'){throw 'HEALTH_ACCOUNT_GROUP_MEMBERSHIP'}
 $m
}
function Invoke-PaytmHealthAccountSetup($Report,[Security.SecureString]$Password,[string]$Run,[scriptblock]$Checkpoint,[switch]$VerifyOnly){
 $c=Get-PaytmHealthAccountContract
 if(-not $VerifyOnly){
  if(@(Get-LocalUser|Where-Object {$_.Name -ieq $c.name}).Count -or (Test-Path -LiteralPath $c.root)){throw 'HEALTH_ACCOUNT_TARGET_EXISTS'}
  $Report.stage='CREATE_DISABLED_ACCOUNT';&$Checkpoint
  $a=New-LocalUser -Name $c.name -Password $Password -Description $c.description -Disabled -ErrorAction Stop
  $Report.accountSid=$a.SID.Value;$Report.createdAccount=$true;&$Checkpoint
  if(-not @(Get-LocalGroupMember -SID 'S-1-5-32-545'|Where-Object {$_.SID.Value -ceq $Report.accountSid}).Count){Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $a -ErrorAction Stop}
  $Report.stage='PROTECTED_STORAGE';&$Checkpoint
  if(Test-Path -LiteralPath $c.root){throw 'HEALTH_ACCOUNT_STORAGE_COLLISION'}
  $null=New-Item -ItemType Directory -Path $c.root -ErrorAction Stop;$Report.createdDirectory=$true;&$Checkpoint
  Set-PaytmAccountDirectoryAcl $c.root $Report.accountSid
  $work=Join-Path $c.root 'work';$null=New-Item -ItemType Directory -Path $work -ErrorAction Stop
  Set-PaytmAccountDirectoryAcl $work $Report.accountSid -Writable
  Write-PaytmAccountNewJson (Join-Path $c.root 'installation.json') ([ordered]@{version=1;runId=$Run;name=$c.name;root=$c.root;sid=$Report.accountSid;containsPrivateKey=$false;passwordExpiryPolicy='WINDOWS_DEFAULT_UNCHANGED'})
  $null=Read-PaytmHealthAccount
  $Report.stage='ENABLE_STANDARD_ACCOUNT';&$Checkpoint
  Enable-LocalUser -SID $Report.accountSid -ErrorAction Stop
 }
 $saved=Read-PaytmHealthAccount;$Report.accountSid=$saved.sid
 if(-not (Get-LocalUser -SID $saved.sid).Enabled){throw 'HEALTH_ACCOUNT_DISABLED'}
 $Report.stage='EXACT_ACCOUNT_PROBE';&$Checkpoint
 $source=New-PaytmAccountProbeSource $saved.sid $Run $c.root
 $info=New-PaytmAccountProbeStartInfo $Password $c.name
 try{$Report.probe=Invoke-PaytmAccountProbeProcess $info $source $Report.probeLaunch}finally{$info.Password=$null}
 &$Checkpoint
 Assert-PaytmAccountProbe $Report.probe $Run
 $null=Read-PaytmHealthAccount
 $Report.status='HEALTH_ACCOUNT_AND_STORAGE_VERIFIED_KEY_CUSTODY_PENDING';$Report.stage='COMPLETE'
}
