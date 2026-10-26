#Requires -Version 5.1
# Shared by the PS7 controller and PS5.1 exact-account worker. No actions on import.
function Get-PaytmKeyContract {
    [pscustomobject]@{root='C:\ProgramData\MarketBrainPaytmGateway\key-custody';
        publicBlob='AAAAC3NzaC1lZDI1NTE5AAAAIN0RPkYq7LMb/7fELzlnQIopM+xrLgxF1gBljdHiEdKJ';
        fingerprint='SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI';
        hostPin='SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI';hostAddress='130.250.191.137';
        accountSid='S-1-5-21-3041730714-102984520-3202743044-1010';
        accountRun='ed64356fd5d84c02b0c156f1fc3ef1b4'}
}
function Get-PaytmKeyFingerprint([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{'SHA256:'+([Convert]::ToBase64String($sha.ComputeHash($Bytes))).TrimEnd('=')}finally{$sha.Dispose()}
}
function Assert-PaytmPrivateKeyAcl($Acl,[string]$Sid) {
    if(-not $Acl.AreAccessRulesProtected -or $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne 'S-1-5-32-544'){throw 'KEY_STAGING_ACL_MISMATCH'}
    $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));$seen=@{}
    if($rules.Count -ne 3){throw 'KEY_STAGING_ACL_MISMATCH'}
    foreach($rule in $rules){
        $id=$rule.IdentityReference.Value
        if($seen.ContainsKey($id) -or $id -cnotin @('S-1-5-18','S-1-5-32-544',$Sid)){throw 'KEY_STAGING_ACL_MISMATCH'};$seen[$id]=$true
        $wanted=if($id -ceq $Sid){[int][Security.AccessControl.FileSystemRights]::Read}else{[int][Security.AccessControl.FileSystemRights]::FullControl}
        $mask=-bnot [int][Security.AccessControl.FileSystemRights]::Synchronize
        if($rule.IsInherited -or $rule.AccessControlType -ne 'Allow' -or $rule.InheritanceFlags -ne 'None' -or $rule.PropagationFlags -ne 'None' -or
            (([int]$rule.FileSystemRights -band $mask) -ne ($wanted -band $mask))){throw 'KEY_STAGING_ACL_MISMATCH'}
    }
}
function Assert-PaytmCustodyController {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not [Environment]::Is64BitProcess -or -not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'KEY_ADMIN_64BIT_REQUIRED'}
}
function New-PaytmCustodyProcess {[Diagnostics.Process]::new()}
function Set-PaytmPrivateKeyAcl([string]$Path,[string]$Sid) {
    $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    # Win32 OpenSSH trusts Administrators ownership. Keep the established owner contract,
    # avoiding arbitrary-owner assignment privileges and gateway WRITE_DAC through ownership.
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach($id in @('S-1-5-18','S-1-5-32-544',$Sid)){
        $rights=if($id -ceq $Sid){'Read'}else{'FullControl'}
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),$rights,'Allow'))
    }
    [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Path),$acl)
    Assert-PaytmPrivateKeyAcl (Get-Acl -LiteralPath $Path) $Sid
}
function Read-PaytmKeyU32([byte[]]$Bytes,[ref]$Offset) {
    if($Offset.Value -lt 0 -or $Offset.Value+4 -gt $Bytes.Length){throw 'KEY_FORMAT_TRUNCATED'}
    [long]$n=0;for($i=0;$i -lt 4;$i++){$n=$n*256+$Bytes[$Offset.Value];$Offset.Value++};$n
}
function Read-PaytmKeyString([byte[]]$Bytes,[ref]$Offset,[int]$Max=8192) {
    $n=Read-PaytmKeyU32 $Bytes $Offset
    if($n -gt $Max -or $Offset.Value+$n -gt $Bytes.Length){throw 'KEY_FORMAT_LENGTH'}
    $value=[byte[]]::new([int]$n);[Array]::Copy($Bytes,$Offset.Value,$value,0,$n);$Offset.Value+=[int]$n
    return ,$value
}
function Assert-PaytmEncryptedKey([byte[]]$FileBytes) {
    if($FileBytes.Length -gt 16384 -or $FileBytes.Length -lt 100 -or @($FileBytes|Where-Object {$_ -gt 127}).Count){throw 'KEY_FILE_SIZE_OR_ENCODING'}
    $text=[Text.Encoding]::ASCII.GetString($FileBytes)
    if($text -cnotmatch '\A-----BEGIN OPENSSH PRIVATE KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)-----END OPENSSH PRIVATE KEY-----(?:\r?\n)?\z'){throw 'KEY_OPENSSH_FORMAT_REQUIRED'}
    try{$bytes=[Convert]::FromBase64String($Matches[1])}catch{throw 'KEY_BASE64_INVALID'}
    try{
        $magic=[Text.Encoding]::ASCII.GetBytes("openssh-key-v1`0")
        if($bytes.Length -lt 15 -or [Convert]::ToBase64String($bytes[0..14]) -cne [Convert]::ToBase64String($magic)){throw 'KEY_FORMAT_MAGIC'}
        $offset=15
        $cipher=[Text.Encoding]::ASCII.GetString((Read-PaytmKeyString $bytes ([ref]$offset) 64))
        $kdf=[Text.Encoding]::ASCII.GetString((Read-PaytmKeyString $bytes ([ref]$offset) 64))
        $options=Read-PaytmKeyString $bytes ([ref]$offset) 256
        if($cipher -cnotin @('aes256-ctr','aes256-cbc') -or $kdf -cne 'bcrypt'){throw 'KEY_ENCRYPTION_REQUIRED'}
        $koff=0;$salt=Read-PaytmKeyString $options ([ref]$koff) 64;$rounds=Read-PaytmKeyU32 $options ([ref]$koff)
        if($salt.Length -lt 16 -or $koff -ne $options.Length -or $rounds -lt 16 -or $rounds -gt 1024){throw 'KEY_KDF_PARAMETERS'}
        if((Read-PaytmKeyU32 $bytes ([ref]$offset)) -ne 1){throw 'KEY_SINGLE_IDENTITY_REQUIRED'}
        $pub=Read-PaytmKeyString $bytes ([ref]$offset) 1024
        if([Convert]::ToBase64String($pub) -cne (Get-PaytmKeyContract).publicBlob){throw 'KEY_IDENTITY_MISMATCH'}
        $encrypted=Read-PaytmKeyString $bytes ([ref]$offset) 8192
        if($encrypted.Length -lt 80 -or $encrypted.Length%16 -ne 0 -or $offset -ne $bytes.Length){throw 'KEY_CIPHERTEXT_LAYOUT'}
        [pscustomobject]@{encrypted=$true;cipher=$cipher;kdf=$kdf;rounds=$rounds;fingerprint=Get-PaytmKeyFingerprint $pub}
    }finally{if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Test-PaytmEncryptedKeyFile([string]$Path) {
    $stream=[IO.File]::Open($Path,'Open','Read','Read');$data=$null
    try{
        if($stream.Length -gt 16384 -or $stream.Length -lt 100){throw 'KEY_INPUT_SIZE'}
        $data=[byte[]]::new([int]$stream.Length);$read=0
        while($read -lt $data.Length){$n=$stream.Read($data,$read,$data.Length-$read);if($n -le 0){throw 'KEY_INPUT_TRUNCATED'};$read+=$n}
        Assert-PaytmEncryptedKey $data
    }finally{if($null -ne $data){[Array]::Clear($data,0,$data.Length)};$stream.Dispose()}
}
function ConvertTo-PaytmPinnedHost([string]$Text) {
    if($Text.Length -gt 8192){throw 'KEY_HOST_SCAN_SIZE'}
    $rows=@($Text.Replace("`r",'').Split("`n")|Where-Object {$_.Trim() -and -not $_.StartsWith('#')})
    if($rows.Count -ne 1 -or $rows[0] -cnotmatch '^130\.250\.191\.137 ssh-rsa ([A-Za-z0-9+/=]+)$'){throw 'KEY_HOST_SCAN_FORMAT'}
    try{$blob=[Convert]::FromBase64String($Matches[1])}catch{throw 'KEY_HOST_SCAN_FORMAT'}
    if((Get-PaytmKeyFingerprint $blob) -cne (Get-PaytmKeyContract).hostPin){throw 'KEY_HOST_PIN_MISMATCH'}
    $off=0;$type=[Text.Encoding]::ASCII.GetString((Read-PaytmKeyString $blob ([ref]$off) 32))
    $exponent=Read-PaytmKeyString $blob ([ref]$off) 16;$modulus=Read-PaytmKeyString $blob ([ref]$off) 1024
    if($type -cne 'ssh-rsa' -or $exponent.Length -eq 0 -or $modulus.Length -lt 256 -or $off -ne $blob.Length){throw 'KEY_HOST_RSA_LAYOUT'}
    # Public-only negative fixture: change a modulus bit, retaining a parseable RSA public-key structure.
    $wrong=[byte[]]$blob.Clone();$wrong[$wrong.Length-1]=$wrong[$wrong.Length-1] -bxor 2
    [pscustomobject]@{knownHost=$rows[0]+"`n";wrongHost='130.250.191.137 ssh-rsa '+[Convert]::ToBase64String($wrong)+"`n";fingerprint=Get-PaytmKeyFingerprint $blob}
}
function Get-PaytmCustodySshArguments([string]$KnownHosts,[string]$PublicKey) {
    foreach($path in @($KnownHosts,$PublicKey)){
        if($path -cnotmatch '^C:\\ProgramData\\MarketBrainPaytmGateway\\key-custody\\[a-z_.]+$'){throw 'KEY_SSH_PATH_INVALID'}
    }
    $argsList=@('-F','none','-N','-T','-4','-v','-p','22','-l','marketbrain-gateway')
    foreach($opt in @('BatchMode=yes','StrictHostKeyChecking=yes','IdentitiesOnly=yes','PasswordAuthentication=no',
        'KbdInteractiveAuthentication=no','PreferredAuthentications=publickey','ForwardAgent=no','ForwardX11=no',
        'ClearAllForwardings=yes','ExitOnForwardFailure=yes','ConnectTimeout=10','ConnectionAttempts=1',
        'ServerAliveInterval=5','ServerAliveCountMax=2','UpdateHostKeys=no','VerifyHostKeyDNS=no',
        'GlobalKnownHostsFile=none','ProxyCommand=none','ProxyJump=none','ControlMaster=no','ControlPath=none',
        'PermitLocalCommand=no','RequestTTY=no','NumberOfPasswordPrompts=0','AddKeysToAgent=no',
        'HostKeyAlgorithms=rsa-sha2-512,rsa-sha2-256',('UserKnownHostsFile='+$KnownHosts.Replace('\','/')),
        ('IdentityFile='+$PublicKey.Replace('\','/')))){$argsList+=@('-o',$opt)}
    $argsList+='130.250.191.137';$argsList
}
function New-PaytmCustodyNativeInfo([string]$Tool,[string[]]$Arguments) {
    if($Tool -cnotin @('ssh.exe','ssh-add.exe','ssh-keyscan.exe')){throw 'KEY_TOOL_NOT_ALLOWED'}
    $info=[Diagnostics.ProcessStartInfo]::new(('C:\Windows\System32\OpenSSH\'+$Tool),(($Arguments|ForEach-Object {ConvertTo-TunnelArgument $_}) -join ' '))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($name in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','SSH_ASKPASS_REQUIRE','DISPLAY','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$info.EnvironmentVariables.Remove($name)}
    $info
}
function Invoke-PaytmCustodyNative([string]$Tool,[string[]]$Arguments,[int]$Seconds=10) {
    $p=[Diagnostics.Process]::new();$p.StartInfo=New-PaytmCustodyNativeInfo $Tool $Arguments;$started=$false;$completed=$false
    try{
        $started=$p.Start();if(-not $started){throw 'KEY_NATIVE_START_FAILED'}
        $handle=[pscustomobject]@{Process=$p;Out=$p.StandardOutput.ReadToEndAsync();Err=$p.StandardError.ReadToEndAsync();Watch=[Diagnostics.Stopwatch]::StartNew();Result=$null}
        $p.StandardInput.Close();$result=Complete-TunnelProcess $handle -LimitSeconds $Seconds;$completed=$true;$result
    }finally{
        if(-not $completed){try{if($started -and -not $p.HasExited){$p.Kill();if(-not $p.WaitForExit(5000)){throw 'KEY_NATIVE_STOP_FAILED'}}}finally{$p.Dispose()}}
    }
}
function Assert-PaytmAgentResult($Result,[ValidateSet('Empty','Expected')]$Expected) {
    if($Result.StoppedByRunner){throw 'KEY_AGENT_TIMEOUT'}
    $text=($Result.Stdout+$Result.Stderr).Trim()
    if($Expected -ceq 'Empty'){
        if($Result.ExitCode -ne 1 -or $text -cne 'The agent has no identities.'){throw 'KEY_AGENT_NOT_EMPTY_OR_UNREACHABLE'}
    }else{
        $lines=@($Result.Stdout.Trim().Split("`n")|Where-Object {$_.Trim()})
        $pattern='^256 '+[regex]::Escape((Get-PaytmKeyContract).fingerprint)+' [^\r\n]* \(ED25519\)$'
        if($Result.ExitCode -ne 0 -or $Result.Stderr.Trim() -or $lines.Count -ne 1 -or $lines[0].Trim() -cnotmatch $pattern){throw 'KEY_AGENT_IDENTITY_MISMATCH'}
    }
}
function Assert-PaytmSigningResult($Result,[bool]$Expected) {
    $exit=if($Expected){0}else{1}
    if($Result.StoppedByRunner -or $Result.ExitCode -ne $exit){throw 'KEY_SIGNING_RESULT_UNEXPECTED'}
}
function Assert-PaytmAuthenticationResult($Result,[bool]$Expected) {
    $authenticated=$Result.Stderr -cmatch '(?m)^Authenticated to 130\.250\.191\.137 .* using "publickey"\.\r?$'
    if($Expected){
        if(-not $authenticated -or -not $Result.StoppedByRunner){throw 'KEY_PINNED_AUTHENTICATION_NOT_ESTABLISHED'}
    }elseif($authenticated -or $Result.StoppedByRunner -or $Result.ExitCode -ne 255 -or $Result.Stderr -notmatch 'Host key verification failed\.'){
        throw 'KEY_WRONG_HOST_NOT_REJECTED'
    }
}
function Get-PaytmSshOutcome($Result) {
    $reason='UNCLASSIFIED'
    foreach($pair in @(@('Host key verification failed\.','HOST_VERIFICATION_FAILED'),@('Permission denied','AUTHENTICATION_DENIED'),
        @('Connection refused','CONNECTION_REFUSED'),@('Connection timed out|Operation timed out','CONNECTION_TIMEOUT'),
        @('No route to host|Network is unreachable','NETWORK_UNREACHABLE'),@('no matching host key type|no matching key exchange','ALGORITHM_MISMATCH'),
        @('Bad configuration option|Unsupported option','CLIENT_OPTION_UNSUPPORTED'),@('Authenticated to .* using "publickey"','PUBLICKEY_AUTHENTICATED'))){
        if($Result.Stderr -match $pair[0]){$reason=$pair[1];break}
    }
    [pscustomobject]@{exitCode=$Result.ExitCode;stoppedByRunner=$Result.StoppedByRunner;elapsedSeconds=$Result.ElapsedSeconds;reason=$reason}
}
function Get-PaytmCustodyIdentity {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    [pscustomobject]@{sid=$id.User.Value;nonAdmin=-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
}
function Invoke-PaytmInteractiveKeyImport([string]$Path) {
    # Inherit the dedicated worker's console: native OpenSSH reads the passphrase from its tty.
    $info=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\OpenSSH\ssh-add.exe',('-k "'+$Path+'"'))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$false
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info;$started=$false
    try{
        $started=$p.Start();if(-not $started){throw 'KEY_IMPORT_START_FAILED'}
        if(-not $p.WaitForExit(180000)){throw 'KEY_IMPORT_INPUT_TIMEOUT'}
        if($p.ExitCode -ne 0){throw 'KEY_IMPORT_FAILED'}
    }finally{try{if($started -and -not $p.HasExited){$p.Kill();if(-not $p.WaitForExit(5000)){throw 'KEY_IMPORT_STOP_FAILED'}}}finally{$p.Dispose()}}
}
function Invoke-PaytmCustodySequence($Plan,$Report,[scriptblock]$Checkpoint) {
    $c=Get-PaytmKeyContract;$pub=Join-Path $c.root 'gateway.pub';$private=Join-Path $c.root 'gateway.openssh'
    $id=Get-PaytmCustodyIdentity
    if($Plan.sid -cne $c.accountSid -or $id.sid -cne $Plan.sid -or -not $id.nonAdmin){throw 'KEY_WORKER_IDENTITY'}
    $Report.identityVerified=$true
    $null=Test-PaytmEncryptedKeyFile $private
    Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Empty
    $Report.stage='IMPORT_FIRST';$Report.importAttempted=$true;&$Checkpoint
    Write-Host 'KEY WINDOW: enter the SSH KEY passphrase at the native prompt (not the Windows account password).'
    Invoke-PaytmInteractiveKeyImport $private;$Report.imported=$true;&$Checkpoint
    Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Expected
    Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $true
    $Report.stage='TARGETED_REVOCATION';&$Checkpoint
    $removed=Invoke-PaytmCustodyNative 'ssh-add.exe' @('-d',$pub)
    if($removed.StoppedByRunner -or $removed.ExitCode -ne 0){throw 'KEY_TARGETED_REVOCATION_FAILED'}
    Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Empty
    Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $false
    $Report.revocationVerified=$true;$Report.stage='IMPORT_SECOND';&$Checkpoint
    Write-Host 'KEY WINDOW: targeted removal passed. Enter the SAME SSH KEY passphrase once more to restore only this key.'
    Invoke-PaytmInteractiveKeyImport $private
    Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Expected
    Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $true
    $Report.reloadVerified=$true;$Report.stage='WRONG_HOST_NEGATIVE';$Report.vpsContactAttempted=$true;&$Checkpoint
    $bad=Invoke-PaytmCustodyNative 'ssh.exe' (Get-PaytmCustodySshArguments (Join-Path $c.root 'wrong_hosts') $pub) 15
    $Report.wrongHostOutcome=Get-PaytmSshOutcome $bad;&$Checkpoint
    Assert-PaytmAuthenticationResult $bad $false;$Report.wrongHostRejected=$true
    $Report.stage='PINNED_AUTHENTICATION';&$Checkpoint
    $good=Invoke-PaytmCustodyNative 'ssh.exe' (Get-PaytmCustodySshArguments (Join-Path $c.root 'known_hosts') $pub) 20
    $Report.authenticationOutcome=Get-PaytmSshOutcome $good;&$Checkpoint
    Assert-PaytmAuthenticationResult $good $true;$Report.pinnedAuthentication=$true;$Report.authenticationSeconds=$good.ElapsedSeconds
    $Report.stage='COMPLETE';&$Checkpoint
}
function New-PaytmCustodyWindowInfo([Security.SecureString]$Password) {
    # Fixed short command; protected worker source lives outside the writable work folder.
    $source="&([scriptblock]::Create([IO.File]::ReadAllText('C:\ProgramData\MarketBrainPaytmGateway\key-custody\worker.ps1')))"
    $info=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('-NoLogo -NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))))
    if($info.FileName.Length+$info.Arguments.Length+4 -gt 1024){throw 'KEY_WINDOW_COMMAND_TOO_LONG'}
    $info.UseShellExecute=$false;$info.CreateNoWindow=$false;$info.WindowStyle='Normal';$info.LoadUserProfile=$true
    $info.UserName='marketbrain-gateway';$info.Domain=$env:COMPUTERNAME;$info.Password=$Password;$info.WorkingDirectory=(Get-PaytmKeyContract).root
    foreach($name in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','SSH_ASKPASS_REQUIRE','DISPLAY','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$info.EnvironmentVariables.Remove($name)}
    $info
}
function New-PaytmCustodyFreshSource([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'KEY_RUN_INVALID'}
    $template=@'
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmGateway\key-custody'
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\library.ps1')))
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\native.ps1')))
$result=[ordered]@{runId='__RUN__';identityVerified=$false;agentIdentityVerified=$false;signingVerified=$false;failure=$null}
try{
 $id=Get-PaytmCustodyIdentity
 if($id.sid -cne (Get-PaytmKeyContract).accountSid -or -not $id.nonAdmin){throw 'IDENTITY'}
 $result.identityVerified=$true
 if([IO.File]::Exists($root+'\gateway.openssh')){throw 'STAGED_KEY_STILL_PRESENT'}
 Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Expected;$result.agentIdentityVerified=$true
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',($root+'\gateway.pub'))) $true;$result.signingVerified=$true
}catch{$result.failure='KEY_FRESH_PROCESS_FAILED'}
$result|ConvertTo-Json -Compress
'@
    $template.Replace('__RUN__',$RunId)
}
