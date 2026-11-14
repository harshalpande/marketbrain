# Definitions only; no private key leaves this machine.
function Assert-PaytmClockKeyDirectory($Acl,[string]$Sid) {
 if(-not $Acl.AreAccessRulesProtected -or $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $Sid){throw 'CLOCK_KEY_DIRECTORY_OWNER_OR_INHERITANCE'}
 $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));$expected=@($Sid,'S-1-5-18','S-1-5-32-544'|Select-Object -Unique);$seen=@{}
 if($rules.Count -ne $expected.Count){throw 'CLOCK_KEY_DIRECTORY_ACL'}
 foreach($r in $rules){
  $id=$r.IdentityReference.Value
  if($seen.ContainsKey($id) -or $id -cnotin $expected -or $r.IsInherited -or $r.AccessControlType -ne 'Allow' -or $r.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $r.InheritanceFlags -ne ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -or $r.PropagationFlags -ne 'None'){throw 'CLOCK_KEY_DIRECTORY_ACL'}
  $seen[$id]=$true
 }
}
function Set-PaytmClockKeyDirectory([string]$Directory) {
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner([Security.Principal.SecurityIdentifier]::new($sid))
 foreach($id in @($sid,'S-1-5-18','S-1-5-32-544'|Select-Object -Unique)){
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
 }
 [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Directory),$acl)
 Assert-PaytmClockKeyDirectory (Get-Acl -LiteralPath $Directory) $sid
}
function Read-PaytmClockPublicKey([string]$Path){
 if((Get-Item -LiteralPath $Path).Length -gt 1024){throw 'CLOCK_KEY_PUBLIC_SIZE'}
 $line=[IO.File]::ReadAllText($Path).Trim()
 if($line -cnotmatch '^ssh-ed25519 ([A-Za-z0-9+/]+={0,2}) marketbrain-clock-reader$'){throw 'CLOCK_KEY_PUBLIC_FORMAT'}
 $blob=$Matches[1];$bytes=[Convert]::FromBase64String($blob)
 if($bytes.Length -ne 51 -or [Convert]::ToBase64String($bytes[0..18]) -cne 'AAAAC3NzaC1lZDI1NTE5AAAAIA=='){throw 'CLOCK_KEY_PUBLIC_LAYOUT'}
 if($blob -ceq (Get-PaytmKeyContract).publicBlob -or $blob -ceq 'AAAAC3NzaC1lZDI1NTE5AAAAIPOVSxqHLjDm2skmoTLWNmCnjAA7Vh6SNf8lHqc0GSOu'){throw 'CLOCK_KEY_REUSED_IDENTITY'}
 [pscustomobject]@{line=$line;blob=$blob;fingerprint=(Get-PaytmKeyFingerprint $bytes)}
}
function New-PaytmClockKeyMaterial([string]$Path){
 $keygen=Join-Path $env:WINDIR 'System32/OpenSSH/ssh-keygen.exe'
 if(-not (Test-Path -LiteralPath $keygen -PathType Leaf)){throw 'CLOCK_KEY_OPENSSH_REQUIRED'}
 Write-Host 'ssh-keygen will ask for a NEW passphrase twice. Use a non-empty passphrase; input is hidden. Do not paste it into chat.'
 & $keygen -t ed25519 -a 64 -f $Path -C marketbrain-clock-reader
 if($LASTEXITCODE -ne 0){throw 'CLOCK_KEY_GENERATION_FAILED'}
}
