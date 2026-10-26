#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "KEY_TEST_FAILED $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed $Name}
function U32([long]$N){return ,[byte[]]@(($N -shr 24 -band 255),($N -shr 16 -band 255),($N -shr 8 -band 255),($N -band 255))}
function SshString([byte[]]$Bytes){return ,[byte[]]((U32 $Bytes.Length)+$Bytes)}
function Ascii([string]$Text){return ,[Text.Encoding]::ASCII.GetBytes($Text)}
function FixtureKey([string]$Cipher='aes256-ctr',[string]$Kdf='bcrypt',[int]$Rounds=16,[string]$Public=(Get-PaytmKeyContract).publicBlob,[int]$Count=1,[int]$EncryptedLength=144){
    # Deliberately synthetic ciphertext: parser fixture, never a usable private key.
    $options=[byte[]]((SshString ([byte[]]::new(16)))+(U32 $Rounds))
    $b=[byte[]]((Ascii "openssh-key-v1`0")+(SshString (Ascii $Cipher))+(SshString (Ascii $Kdf))+(SshString $options)+(U32 $Count)+(SshString ([Convert]::FromBase64String($Public)))+(SshString ([byte[]]::new($EncryptedLength))))
    return ,(Ascii ("-----BEGIN OPENSSH PRIVATE KEY-----`n"+[Convert]::ToBase64String($b)+"`n-----END OPENSSH PRIVATE KEY-----`n"))
}
$valid=FixtureKey
$parsed=Assert-PaytmEncryptedKey $valid
Check ($parsed.encrypted -and $parsed.fingerprint -ceq (Get-PaytmKeyContract).fingerprint) 'encrypted header and approved public identity'
$null=Assert-PaytmEncryptedKey (FixtureKey -Cipher aes256-cbc);$script:checks++
foreach($case in @(@('none','none',16,1,144),@('aes128-ctr','bcrypt',16,1,144),@('aes256-ctr','none',16,1,144),@('aes256-ctr','bcrypt',1,1,144),@('aes256-ctr','bcrypt',1025,1,144),@('aes256-ctr','bcrypt',16,2,144),@('aes256-ctr','bcrypt',16,1,1),@('aes256-ctr','bcrypt',16,1,145))){
    Reject {Assert-PaytmEncryptedKey (FixtureKey -Cipher $case[0] -Kdf $case[1] -Rounds $case[2] -Count $case[3] -EncryptedLength $case[4])} 'reject malformed/unencrypted/expensive input'
}
$wrong=[Convert]::FromBase64String((Get-PaytmKeyContract).publicBlob);$wrong[-1]=$wrong[-1] -bxor 1
Reject {Assert-PaytmEncryptedKey (FixtureKey -Public ([Convert]::ToBase64String($wrong)))} 'wrong gateway identity'
Reject {Assert-PaytmEncryptedKey (Ascii 'PuTTY-User-Key-File-3: ssh-ed25519')} 'PPK is not accepted'
Reject {Assert-PaytmEncryptedKey ([byte[]]::new(16385))} 'oversized input'
Reject {Assert-PaytmEncryptedKey ([byte[]]@($valid+1))} 'trailing material'
$truncated=[Text.Encoding]::ASCII.GetString($valid).Replace('b3BlbnNzaC1rZXktdjE','xxxxxxxxxxxxxxxxxxx')
Reject {Assert-PaytmEncryptedKey (Ascii $truncated)} 'magic corruption'
$off=0;Reject {Read-PaytmKeyString ([byte[]]@(255,255,255,255)) ([ref]$off)} 'wire integer bounds'
$sid=(Get-PaytmKeyContract).accountSid
$acl=[Security.AccessControl.FileSecurity]::new();$acl.SetSecurityDescriptorSddlForm(('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FR;;;'+$sid+')'))
Assert-PaytmPrivateKeyAcl $acl $sid;$script:checks++
$acl.SetAccessRuleProtection($false,$true);Reject {Assert-PaytmPrivateKeyAcl $acl $sid} 'unprotected private file'
$info=New-PaytmCustodyWindowInfo $null
Check (($info.FileName.Length+$info.Arguments.Length+4) -le 1024) 'credentialed short command'
Check (-not $info.CreateNoWindow -and $info.WindowStyle -eq 'Normal' -and -not $info.RedirectStandardInput -and -not $info.RedirectStandardOutput) 'visible real console not stdin pipe'
Check ($info.UserName -ceq 'marketbrain-gateway' -and $info.LoadUserProfile -and -not $info.UseShellExecute) 'exact account profile'
Check ($info.Arguments -notmatch 'ExecutionPolicy|Bypass|NoExit|NonInteractive') 'no policy weakening or noninteractive import'
$nativeInfo=New-PaytmCustodyNativeInfo 'ssh-add.exe' @('-T','C:\path with spaces\gateway.pub')
Check ($nativeInfo.CreateNoWindow -and $nativeInfo.RedirectStandardInput -and $nativeInfo.WindowStyle -eq 'Hidden') 'noninteractive verification is hidden'
Check (-not $nativeInfo.EnvironmentVariables.ContainsKey('SSH_AUTH_SOCK') -and -not $nativeInfo.EnvironmentVariables.ContainsKey('SSH_ASKPASS')) 'native tests use default account agent not inherited override'
Reject {New-PaytmCustodyNativeInfo 'cmd.exe' @('/c','anything')} 'native tool allowlist'
$source=New-PaytmCustodyFreshSource ('a'*32);Check ($source.Contains('STAGED_KEY_STILL_PRESENT') -and $source.Contains("@('-T'")) 'fresh process no private-file fallback'
Reject {New-PaytmCustodyFreshSource '../bad'} 'run binding'
function Result([int]$Exit,[string]$Out='',[string]$Err='',[bool]$Stopped=$false){[pscustomobject]@{ExitCode=$Exit;Stdout=$Out;Stderr=$Err;StoppedByRunner=$Stopped;ElapsedSeconds=20}}
$empty=Result 1 'The agent has no identities.'
$listed=Result 0 ('256 '+(Get-PaytmKeyContract).fingerprint+' test (ED25519)')
Assert-PaytmAgentResult $empty Empty;$script:checks++
Assert-PaytmAgentResult $listed Expected;$script:checks++
foreach($bad in @((Result 2),(Result 0 ($listed.Stdout+"`n"+$listed.Stdout)),(Result 0 '256 SHA256:wrong test (ED25519)'),(Result 0 $listed.Stdout 'warning'),(Result 0 $listed.Stdout '' $true))){Reject {Assert-PaytmAgentResult $bad Expected} 'wrong/multiple/unreachable/timed-out agent'}
Assert-PaytmSigningResult (Result 0) $true;$script:checks++
Assert-PaytmSigningResult (Result 1) $false;$script:checks++
Reject {Assert-PaytmSigningResult (Result 2) $false} 'unreachable agent is not isolation'
$goodAuth=Result -1 '' 'Authenticated to 130.250.191.137 ([130.250.191.137]:22) using "publickey".' $true
$badAuth=Result 255 '' 'Host key verification failed.'
Assert-PaytmAuthenticationResult $goodAuth $true;$script:checks++
Assert-PaytmAuthenticationResult $badAuth $false;$script:checks++
Check ((Get-PaytmSshOutcome $badAuth).reason -ceq 'HOST_VERIFICATION_FAILED') 'safe host failure classification'
Check ((Get-PaytmSshOutcome $goodAuth).reason -ceq 'PUBLICKEY_AUTHENTICATED') 'safe success classification'
Check ((Get-PaytmSshOutcome (Result 255 '' 'Permission denied (publickey).')).reason -ceq 'AUTHENTICATION_DENIED') 'safe authentication denial'
Reject {Assert-PaytmAuthenticationResult (Result 255 '' 'Connection timed out') $false} 'network failure is not negative host proof'
Reject {Assert-PaytmAuthenticationResult (Result 0 '' $goodAuth.Stderr) $true} 'authentication must remain connected until deliberate stop'
Reject {Assert-PaytmAuthenticationResult $goodAuth $false} 'negative cannot authenticate'
$argsList=Get-PaytmCustodySshArguments 'C:\ProgramData\MarketBrainPaytmGateway\key-custody\known_hosts' 'C:\ProgramData\MarketBrainPaytmGateway\key-custody\gateway.pub'
foreach($required in @('-N','-T','StrictHostKeyChecking=yes','ClearAllForwardings=yes','BatchMode=yes','ForwardAgent=no','IdentitiesOnly=yes')){Check ($required -cin $argsList) $required}
foreach($denied in @('-L','-D','-R','-A','-tt')){Check ($denied -cnotin $argsList) 'no forward/shell authority'}
Reject {Get-PaytmCustodySshArguments 'C:\untrusted\known_hosts' 'C:\untrusted\id'} 'fixed SSH paths'
$effective=Invoke-PaytmCustodyNative 'ssh.exe' (@('-G')+$argsList) 10
Check ($effective.ExitCode -eq 0 -and -not $effective.StoppedByRunner) 'native SSH config parse without connecting'
Check ($effective.Stdout -match '(?m)^clearallforwardings yes\r?$' -and $effective.Stdout -notmatch '(?m)^(localforward|remoteforward) ') 'native no-forward config'
Check ($effective.Stdout -match '(?m)^sessiontype none\r?$' -and $effective.Stdout -match '(?m)^hostkeyalgorithms rsa-sha2-512,rsa-sha2-256\r?$') 'native no-session pinned algorithm'
# Positive and negative host wire parsing, with an explicitly synthetic public fixture pin.
$originalContract=(Get-Item Function:Get-PaytmKeyContract).ScriptBlock
$rsa=[byte[]]((SshString (Ascii 'ssh-rsa'))+(SshString ([byte[]]@(1,0,1)))+(SshString ([byte[]]::new(385))))
$script:fakePin=Get-PaytmKeyFingerprint $rsa
function Get-PaytmKeyContract {[pscustomobject]@{hostPin=$script:fakePin}}
$hostLine='130.250.191.137 ssh-rsa '+[Convert]::ToBase64String($rsa)
$pins=ConvertTo-PaytmPinnedHost $hostLine
Check ($pins.knownHost.Trim() -ceq $hostLine -and $pins.wrongHost -cne $pins.knownHost) 'public negative host fixture'
Reject {ConvertTo-PaytmPinnedHost ($hostLine+"`n"+$hostLine)} 'duplicate host scan'
Reject {ConvertTo-PaytmPinnedHost ($hostLine.Replace('130.250.191.137','127.0.0.1'))} 'wrong scan target'
Reject {ConvertTo-PaytmPinnedHost $pins.wrongHost} 'wrong scanned pin'
Set-Item Function:Get-PaytmKeyContract $originalContract
# Run the actual worker orchestration with a synthetic ciphertext file and mocked identity/native operations.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-key-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
[IO.File]::WriteAllBytes((Join-Path $temp 'gateway.openssh'),$valid)
$realContract=Get-PaytmKeyContract;$realContract.root=$temp
function Get-PaytmKeyContract {$realContract}
function Get-PaytmCustodyIdentity {[pscustomobject]@{sid=if($script:scenario -ceq 'identity'){'wrong'}else{$realContract.accountSid};nonAdmin=$script:scenario -cne 'admin'}}
function Invoke-PaytmInteractiveKeyImport($Path){$script:imports++;if($script:scenario -ceq 'importFail'){throw 'KEY_IMPORT_FAILED'};$script:loaded=$true}
function Get-PaytmCustodySshArguments($KnownHosts,$PublicKey){@($KnownHosts)}
function Invoke-PaytmCustodyNative($Tool,[string[]]$Arguments,$Seconds){
    $script:calls+=@($Tool+' '+($Arguments -join ' '))
    if($Tool -ceq 'ssh.exe'){
        if($Arguments[0] -like '*wrong_hosts'){if($script:scenario -ceq 'negativeNetwork'){return Result 255 '' 'network failure'};return $badAuth}
        if($script:scenario -ceq 'authFail'){return Result 255 '' 'Permission denied'};return $goodAuth
    }
    switch($Arguments[0]){
        '-l' {if($script:loaded){return $listed}else{return $empty}}
        '-T' {if($script:scenario -ceq 'signFail'){return Result 2};if($script:loaded){return Result 0}else{return Result 1}}
        '-d' {if($script:scenario -ceq 'revokeFail'){return Result 1};$script:loaded=$false;return Result 0}
        default {throw 'unexpected fixture native call'}
    }
}
foreach($case in @('pass','identity','admin','nonempty','importFail','signFail','revokeFail','negativeNetwork','authFail')){
    $script:scenario=$case;$script:loaded=$case -ceq 'nonempty';$script:imports=0;$script:calls=@();$r=[ordered]@{};$failed=$false
    try{Invoke-PaytmCustodySequence ([pscustomobject]@{sid=$realContract.accountSid}) $r {}}catch{$failed=$true}
    Check ($failed -eq ($case -cne 'pass')) ('worker case '+$case)
    Check (-not (($script:calls -join '|') -cmatch 'ssh-add.exe -D|ssh.exe .* -L ')) 'no broad removal or forwarding'
    if($case -ceq 'pass'){Check ($script:imports -eq 2 -and $r.revocationVerified -and $r.pinnedAuthentication -and $script:loaded) 'targeted revoke and reload with auth'}
    if($case -cin @('identity','admin','nonempty')){Check ($script:imports -eq 0) 'pre-import stops'}
    if($case -ceq 'negativeNetwork'){Check (-not $r.pinnedAuthentication) 'negative failure stops positive authentication'}
}
foreach($file in @('PaytmGatewayKeyCustody.ps1','PaytmGatewayKeyWorker.ps1','InstallPaytmGatewayKeyCustody.ps1')){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$t,[ref]$e);Check ($e.Count -eq 0) ('syntax '+$file)
    $commands=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()})
    foreach($blocked in @('Set-Service','Start-Service','Stop-Service','New-LocalUser','Remove-LocalUser','Register-ScheduledTask','Invoke-WebRequest')){Check ($blocked -cnotin $commands) ('no unrelated mutation '+$blocked)}
}
Write-Host "PASS: $script:checks key-custody assertions; 9 mocked worker sequences; native SSH -G only. No real private key, agent import, account/service changes or network connection."
