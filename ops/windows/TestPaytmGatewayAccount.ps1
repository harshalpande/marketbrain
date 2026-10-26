#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "ACCOUNT_TEST_FAILED $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Name){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad $Name}
$sid='S-1-5-21-111-222-333-1001';$run='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$progress=@(Get-PaytmReadinessProgress)
Check ($progress.Count -eq 6) 'six progress groups'
Check ($progress[0].percent -eq 100 -and $progress[1].percent -eq 20) 'accepted evidence percentages'
Check (@($progress[2..5]|Where-Object {$_.percent -ne 0}).Count.Equals(0)) 'no speculative runtime credit'
$inventory=[pscustomobject]@{elevated=$true;native64Bit=$true;toolsPresent=$true;agentImage='"C:\Windows\System32\OpenSSH\ssh-agent.exe"';agentStartName='LocalSystem';accountExists=$false;rootExists=$false;agentStatus='Stopped';agentStartType='Disabled';secondaryLogonStartType='Manual';agentControlError=0}
Assert-PaytmAccountInventory $inventory Apply;$script:checks++
foreach($field in @('elevated','native64Bit','toolsPresent')){$bad=$inventory.PSObject.Copy();$bad.$field=$false;Reject {Assert-PaytmAccountInventory $bad Apply} $field}
foreach($field in @('accountExists','rootExists')){$bad=$inventory.PSObject.Copy();$bad.$field=$true;Reject {Assert-PaytmAccountInventory $bad Apply} $field}
$bad=$inventory.PSObject.Copy();$bad.agentControlError=5;Reject {Assert-PaytmAccountInventory $bad Apply} 'SCM denied even when elevated'
foreach($pair in @(@('agentImage','C:\untrusted.exe'),@('agentStartName','Other'),@('agentStatus','Running'),@('agentStartType','Manual'),@('secondaryLogonStartType','Disabled'))){
    $bad=$inventory.PSObject.Copy();$bad.($pair[0])=$pair[1];Reject {Assert-PaytmAccountInventory $bad Apply} $pair[0]
}
foreach($writable in @($false,$true)){
    $acl=New-PaytmAccountAcl $sid -Writable:$writable
    Assert-PaytmAccountAcl $acl $sid -Writable:$writable;$script:checks++
    # Native Windows security-descriptor serialization/canonicalization, without altering real accounts.
    $bytes=$acl.GetSecurityDescriptorBinaryForm()
    $roundTrip=[Security.AccessControl.DirectorySecurity]::new();$roundTrip.SetSecurityDescriptorBinaryForm($bytes)
    Assert-PaytmAccountAcl $roundTrip $sid -Writable:$writable;$script:checks++
    Reject {Assert-PaytmAccountAcl $roundTrip $sid -Writable:(-not $writable)} 'wrong write permission'
}
foreach($kind in @('owner','inheritance','extraIdentity','deny','overgrant')){
    $acl=New-PaytmAccountAcl $sid
    switch($kind){
        owner {$acl.SetOwner([Security.Principal.SecurityIdentifier]::new($sid))}
        inheritance {$acl.SetAccessRuleProtection($false,$true)}
        extraIdentity {$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'))}
        deny {$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'Read','Deny'))}
        overgrant {$acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    }
    Reject {Assert-PaytmAccountAcl $acl $sid} "ACL $kind"
}
$first=ConvertTo-SecureString 'FixtureOnly-NOT-A-REAL-PASSWORD-1' -AsPlainText -Force
$same=ConvertTo-SecureString 'FixtureOnly-NOT-A-REAL-PASSWORD-1' -AsPlainText -Force
$other=ConvertTo-SecureString 'FixtureOnly-NOT-A-REAL-PASSWORD-2' -AsPlainText -Force
$short=ConvertTo-SecureString 'short' -AsPlainText -Force
try{
    Check (Test-PaytmAccountPasswords $first $same) 'matching secure strings'
    Check (-not (Test-PaytmAccountPasswords $first $other)) 'different secure strings'
    Check (-not (Test-PaytmAccountPasswords $short $short)) 'short password'
}finally{foreach($secret in @($first,$same,$other,$short)){$secret.Dispose()}}
foreach($vector in @(
    @('1234567890123','1234567890123','ACCOUNT_PASSWORD_TOO_SHORT'),
    @('12345678901234','12345678901234','CONFIRMED'),
    @('12345678901234','123456789012345','ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH'),
    @('12345678901234','12345678901235','ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH'),
    @('ABCDEFGHIJKLMN','abcdefghijklmn','ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH'),
    @(' 12345678901234','12345678901234 ','ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH'),
    @('unicode-é-密码-12345','unicode-é-密码-12345','CONFIRMED'),
    @('unicode-é-密码-12345','unicode-é-密码-12346','ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH')
)){
    $a=ConvertTo-SecureString $vector[0] -AsPlainText -Force;$b=ConvertTo-SecureString $vector[1] -AsPlainText -Force
    try{Check ((Get-PaytmAccountPasswordResult $a $b) -ceq $vector[2]) 'exact password outcome'}finally{$a.Dispose();$b.Dispose()}
}
$empty=[Security.SecureString]::new()
try{
    Check ((Get-PaytmAccountPasswordResult $empty $empty) -ceq 'ACCOUNT_PASSWORD_TOO_SHORT') 'empty password'
    Check ((Get-PaytmAccountPasswordResult $null $empty) -ceq 'ACCOUNT_PASSWORD_INPUT_MISSING') 'missing input'
}finally{$empty.Dispose()}
$probe=[pscustomobject]@{version=1;runId=$run;sidMatched=$true;nonAdmin=$true;protectedWriteDenied=$true;workWriteReadDelete=$true;agentEmpty=$true;agentExit=1;failure=$null}
Assert-PaytmAccountProbe $probe $run;$script:checks++
foreach($field in @('sidMatched','nonAdmin','protectedWriteDenied','workWriteReadDelete','agentEmpty')){
    $bad=$probe.PSObject.Copy();$bad.$field=$false;Reject {Assert-PaytmAccountProbe $bad $run} "probe $field"
    $bad.$field='true';Reject {Assert-PaytmAccountProbe $bad $run} "probe typed $field"
}
foreach($pair in @(@('agentExit',0),@('agentExit',2),@('version',2),@('runId','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),@('failure','FAILED'))){
    $bad=$probe.PSObject.Copy();$bad.($pair[0])=$pair[1];Reject {Assert-PaytmAccountProbe $bad $run} "probe $($pair[0])"
}
Reject {New-PaytmAccountProbeSource 'bad' $run} 'SID injection'
Reject {New-PaytmAccountProbeSource $sid 'bad'} 'run injection'
Reject {Assert-PaytmAccountPath 'relative'} 'relative path'
$probeSource=New-PaytmAccountProbeSource $sid $run
$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput($probeSource,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'child source parses'
# Test the real production bootstrap/stdin/collection code, not a separate unrestricted
# same-user -EncodedCommand path. Clear credentials ONLY in this local test fixture.
function New-CurrentUserProbeFixture {
    $info=New-PaytmAccountProbeStartInfo $null
    $info.UserName='';$info.Domain='';$info.Password=$null;$info.LoadUserProfile=$false
    $info.WorkingDirectory=[IO.Path]::GetTempPath()
    $info
}
$credentialFixture=ConvertTo-SecureString 'FixtureOnly-NOT-A-REAL-PASSWORD-1' -AsPlainText -Force
try{
    $info=New-PaytmAccountProbeStartInfo $credentialFixture
    Check ($info.UserName -ceq 'marketbrain-gateway' -and $info.Domain -ceq $env:COMPUTERNAME -and $info.LoadUserProfile) 'exact credential target and profile'
    Check ($info.FileName -ceq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -and $info.WorkingDirectory -ceq 'C:\ProgramData\MarketBrainPaytmGateway') 'absolute runtime paths'
    Check ($info.RedirectStandardInput -and $info.RedirectStandardOutput -and $info.RedirectStandardError -and -not $info.UseShellExecute) 'private redirected handles'
    Check ($info.WindowStyle -eq 'Hidden' -and $info.CreateNoWindow) 'hidden launch intent'
    Check (($info.FileName.Length+$info.Arguments.Length+4) -le 1024 -and $info.Arguments -notmatch 'FixtureOnly') 'alternate-user command bound and no password arguments'
    Check ($info.StandardInputEncoding.WebName -ceq 'utf-8') 'explicit stdin encoding'
    foreach($name in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){Check (-not $info.EnvironmentVariables.ContainsKey($name)) "environment isolation $name"}
    $info.Password=$null
}finally{$credentialFixture.Dispose()}
$boundary=New-CurrentUserProbeFixture
$boundary.Arguments='x'*(1024-$boundary.FileName.Length-4)
Assert-PaytmAccountProbeCommandLine $boundary;$script:checks++
$boundary.Arguments+='x';Reject {Assert-PaytmAccountProbeCommandLine $boundary} '1025 rejects before launch'
$legacyLength=51+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeSource)).Length
Check ($legacyLength -gt 1024) 'previous full-source launch exceeds alternate-user contract'
$diag=[ordered]@{}
$wrongIdentity=Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) $probeSource $diag
Check ($diag.processStarted -and $diag.exitCode -eq 0 -and $diag.stopConfirmed -and $diag.transport -ceq 'UTF8_STDIN') 'native production transport executes and cleans up'
Check (-not $wrongIdentity.sidMatched -and $wrongIdentity.failure -ceq 'ACCOUNT_PROBE_CHECK_FAILED' -and $null -eq $wrongIdentity.agentExit) 'wrong identity fails before agent access'
Check ($wrongIdentity.checkStage -ceq 'IDENTITY') 'safe child stage retained'
Reject {Assert-PaytmAccountProbe $wrongIdentity $run} 'failed real child cannot pass acceptance'
$largeSource=('# '+('x'*12000)+"`n"+'[pscustomobject]@{value="é-密码"}|ConvertTo-Json -Compress')
$diag=[ordered]@{};$large=Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) $largeSource $diag
# Windows stdout codepage is not assumed UTF-8; use ASCII numeric output for the encoding assertion below.
Check ($diag.sourceCharacters -gt 1024 -and $diag.commandLineCharacters -le 1024 -and $diag.stopConfirmed) 'large source absent from argv'
$diag=[ordered]@{};$unicode=Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) '[pscustomobject]@{code=[int][char]"é"}|ConvertTo-Json -Compress' $diag
Check ($unicode.code -eq 233) 'UTF8 source survives native stdin transport'
foreach($case in @(
    @{name='malformed';source='Write-Output "not-json"';error='ACCOUNT_PROBE_JSON_INVALID'},
    @{name='empty';source='$null';error='ACCOUNT_PROBE_JSON_INVALID'},
    @{name='array';source='Write-Output "[{}]"';error='ACCOUNT_PROBE_JSON_INVALID'},
    @{name='oversized';source='Write-Output ("x"*5000)';error='ACCOUNT_PROBE_OUTPUT_FAILED'},
    @{name='nonzero';source='exit 7';error='ACCOUNT_PROBE_OUTPUT_FAILED'},
    @{name='syntax';source='bad syntax }';error='ACCOUNT_PROBE_OUTPUT_FAILED'}
)){
    $diag=[ordered]@{};$message=$null
    try{$null=Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) $case.source $diag}catch{$message=$_.Exception.Message}
    Check ($message -ceq $case.error -and $diag.stopConfirmed) "native negative $($case.name)"
}
$diag=[ordered]@{};$message=$null
try{$null=Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) 'Start-Sleep -Seconds 30' $diag -TimeoutMilliseconds 100}catch{$message=$_.Exception.Message}
Check ($message -ceq 'ACCOUNT_PROBE_TIMEOUT' -and $diag.stopConfirmed) 'timeout kills only owned child'
$diag=[ordered]@{};$missing=New-CurrentUserProbeFixture;$missing.FileName=Join-Path ([IO.Path]::GetTempPath()) ('missing-'+[guid]::NewGuid().ToString('N')+'.exe')
Reject {Invoke-PaytmAccountProbeProcess $missing '$null' $diag} 'native start failure'
Check ($diag.stage -ceq 'START_PROCESS' -and -not $diag.processStarted) 'start failure retains safe metadata'
Reject {Invoke-PaytmAccountProbeProcess (New-CurrentUserProbeFixture) ('x'*32769) ([ordered]@{})} 'source size guard'
# Full launcher orchestration with account/service/filesystem operations replaced by explicit mocks.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-account-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$mock=@'
$global:realInventoryAssertion=${function:Assert-PaytmAccountInventory}
function Assert-PaytmAccountInventory($Inventory,$Mode){$Inventory.elevated=$true;$Inventory.native64Bit=$true;&$global:realInventoryAssertion $Inventory $Mode}
function Import-Module {param($Name,$ErrorAction)}
function Get-PaytmAgentControlAccess {if($global:accountFixture.scmDenied){return 5};0}
function Get-PaytmLocalMembershipSnapshot {if($global:accountFixture.groupQueryDenied){throw 'ACCOUNT_FIXTURE_GROUP_QUERY_DENIED'}}
function Get-PaytmReadinessProgress {foreach($id in 1..6){[pscustomobject]@{id="G$id";percent=if($id -eq 1){100}elseif($id -eq 2){20}else{0}}}}
function Get-LocalUser {param($Name,$SID,$ErrorAction) if($global:accountFixture.exists){[pscustomobject]@{Name='marketbrain-gateway';SID=[pscustomobject]@{Value='S-1-5-21-111-222-333-1001'};Enabled=$global:accountFixture.enabled;Description='MarketBrain gateway account'}}}
function New-LocalUser {param($Name,$Password,$Description,[switch]$Disabled,$ErrorAction) $global:accountFixture.exists=$true;$global:accountFixture.mutations++;Get-LocalUser}
function Get-LocalGroupMember {param($SID,$ErrorAction) if($global:accountFixture.autoMember){Get-LocalUser}}
function Add-LocalGroupMember {param($SID,$Member,$ErrorAction) $global:accountFixture.mutations++;$global:accountFixture.groupAdds++}
function Enable-LocalUser {param($SID,$ErrorAction) $global:accountFixture.enabled=$true;$global:accountFixture.mutations++}
function Disable-LocalUser {param($SID,$ErrorAction) $global:accountFixture.enabled=$false;$global:accountFixture.mutations++}
function Get-Service {param($Name,$ErrorAction)
    $s=if($Name -eq 'seclogon'){[pscustomobject]@{StartType='Manual'}}else{[pscustomobject]@{Status=$global:accountFixture.agentStatus;StartType=$global:accountFixture.agentStartType}}
    $s|Add-Member ScriptMethod WaitForStatus {param($Status,$Timeout)};$s
}
function Get-CimInstance {param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction) [pscustomobject]@{PathName='C:\Windows\System32\OpenSSH\ssh-agent.exe';StartName='LocalSystem'}}
function Set-Service {param($Name,$StartupType,$ErrorAction) $global:accountFixture.agentStartType=$StartupType;$global:accountFixture.mutations++}
function Start-Service {param($Name,$ErrorAction) if($global:accountFixture.failAgent){throw 'ACCOUNT_FIXTURE_AGENT_DENIED'};$global:accountFixture.agentStatus='Running';$global:accountFixture.mutations++}
function Assert-PaytmAccountPath($Path){$Path}
function Set-PaytmAccountDirectoryAcl {param($Path,$AccountSid,[switch]$Writable)}
function Write-PaytmAccountNewJson {param($Path,$Value) $global:accountFixture.manifest=$Value}
function Read-PaytmOwnedAccount {if(-not $global:accountFixture.exists){throw 'ACCOUNT_FIXTURE_NOT_OWNED'};[pscustomobject]@{sid='S-1-5-21-111-222-333-1001'}}
function Invoke-PaytmAccountProbe {param($Sid,$RunId,$Password,$Diagnostics)
    if($global:accountFixture.failProbe){throw 'ACCOUNT_PROBE_FAILED'}
    $Diagnostics.stage='COMPLETE'
    [pscustomobject]@{version=1;runId=$RunId;sidMatched=$true;nonAdmin=$true;protectedWriteDenied=$true;workWriteReadDelete=$true;agentEmpty=(-not $global:accountFixture.childFailure);agentExit=1;checkStage=if($global:accountFixture.childFailure){'AGENT_QUERY'}else{'COMPLETE'};failure=if($global:accountFixture.childFailure){'ACCOUNT_PROBE_CHECK_FAILED'}else{$null}}
}
function Test-Path {param($LiteralPath,$PathType) if($LiteralPath -eq 'C:\ProgramData\MarketBrainPaytmGateway'){return $global:accountFixture.rootExists};Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
function New-Item {param($ItemType,$Path,[switch]$Force,$ErrorAction) if($Path.StartsWith('C:\ProgramData\MarketBrainPaytmGateway')){$global:accountFixture.rootExists=$true;return};Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){
        $index=$global:accountFixture.passwordReads;$global:accountFixture.passwordReads++
        if($global:accountFixture.inputFailure -and $index -eq 1){throw 'ACCOUNT_PASSWORD_INPUT_CANCELLED'}
        $value=if($index -lt $global:accountFixture.passwordInputs.Count){$global:accountFixture.passwordInputs[$index]}else{'FixtureOnly-NOT-A-REAL-PASSWORD-1'}
        $secret=ConvertTo-SecureString $value -AsPlainText -Force
        $global:accountFixture.secrets.Add($secret);return $secret
    }
    if($global:accountFixture.cancel){return 'CANCEL'};if($Prompt -like '*DISABLE-ACCOUNT*'){return 'DISABLE-ACCOUNT'};'PROVISION-ACCOUNT'
}
'@
[IO.File]::WriteAllText((Join-Path $temp 'PaytmGatewayAccount.ps1'),([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1'))+"`n"+$mock))
[IO.File]::WriteAllText((Join-Path $temp 'InstallPaytmGatewayAccount.ps1'),[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'InstallPaytmGatewayAccount.ps1')))
$scenarios=@('clean','autoMember','cancel','collision','scmDenied','groupQueryDenied','agentFailure','probeFailure','verify','disable','shortThenSuccess','mismatchThenSuccess','thirdAttemptSuccess','shortExhausted','mismatchExhausted','inputCancelled','verifyChildFailure')
foreach($scenario in $scenarios){
    $global:accountFixture=@{exists=($scenario -in @('collision','verify','disable'));rootExists=($scenario -in @('verify','disable'));enabled=($scenario -in @('verify','disable'));mutations=0;groupAdds=0;autoMember=($scenario -ceq 'autoMember');agentStatus='Stopped';agentStartType='Disabled';cancel=($scenario -ceq 'cancel');scmDenied=($scenario -ceq 'scmDenied');groupQueryDenied=($scenario -ceq 'groupQueryDenied');failAgent=($scenario -ceq 'agentFailure');failProbe=($scenario -ceq 'probeFailure')}
    $global:accountFixture.passwordReads=0;$global:accountFixture.passwordInputs=@()
    $global:accountFixture.secrets=[Collections.Generic.List[Security.SecureString]]::new()
    $global:accountFixture.inputFailure=$scenario -ceq 'inputCancelled'
    $global:accountFixture.childFailure=$scenario -ceq 'verifyChildFailure'
    if($scenario -ceq 'verifyChildFailure'){$global:accountFixture.exists=$true;$global:accountFixture.rootExists=$true;$global:accountFixture.enabled=$true}
    switch($scenario){
        shortThenSuccess {$global:accountFixture.passwordInputs=@('FixtureOnly','FixtureOnly')}
        mismatchThenSuccess {$global:accountFixture.passwordInputs=@('FixtureOnly-NOT-A-REAL-PASSWORD-1','FixtureOnly-NOT-A-REAL-PASSWORD-2')}
        thirdAttemptSuccess {$global:accountFixture.passwordInputs=@('FixtureOnly','FixtureOnly','FixtureOnly-NOT-A-REAL-PASSWORD-1','FixtureOnly-NOT-A-REAL-PASSWORD-2')}
        shortExhausted {$global:accountFixture.passwordInputs=@('FixtureOnly')*6}
        mismatchExhausted {$global:accountFixture.passwordInputs=@('FixtureOnly-NOT-A-REAL-PASSWORD-1','FixtureOnly-NOT-A-REAL-PASSWORD-2')*3}
    }
    if($scenario -in @('verify','verifyChildFailure')){$global:accountFixture.agentStatus='Running';$global:accountFixture.agentStartType='Automatic'}
    $mode=if($scenario -in @('verify','verifyChildFailure')){'Verify'}elseif($scenario -ceq 'disable'){'Disable'}else{'Apply'}
    $outDir=Join-Path $temp $scenario;$failed=$false
    $console=[Collections.Generic.List[string]]::new()
    try{& (Join-Path $temp 'InstallPaytmGatewayAccount.ps1') -Mode $mode -OutputDirectory $outDir 6>&1 | ForEach-Object {$console.Add([string]$_);Write-Host $_}}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $outDir -Filter '*.json')
    Check ($files.Count -eq 1) "one report $scenario"
    $report=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    $expectedFailure=$scenario -in @('cancel','collision','scmDenied','groupQueryDenied','agentFailure','probeFailure','shortExhausted','mismatchExhausted','inputCancelled','verifyChildFailure')
    Check ($failed -eq $expectedFailure) "outcome $scenario"
    Check (-not $report.gatewayActivated -and -not $report.ordersEnabled -and -not $report.sshKeysImported -and -not $report.vpsContacted) "authority $scenario"
    Check ((Get-Content -LiteralPath $files[0].FullName -Raw) -notmatch 'FixtureOnly') "no password $scenario"
    Check (($console -join "`n") -notmatch 'FixtureOnly') "no console password $scenario"
    foreach($secret in $global:accountFixture.secrets){Reject {$copy=$secret.Copy();$copy.Dispose()} "secure input disposed $scenario"}
    if($scenario -in @('cancel','collision','scmDenied','groupQueryDenied','verify','shortExhausted','mismatchExhausted','inputCancelled','verifyChildFailure')){Check ($global:accountFixture.mutations -eq 0) "no mutation $scenario"}
    if($scenario -ceq 'verifyChildFailure'){Check ($report.probe.checkStage -ceq 'AGENT_QUERY' -and $report.probeLaunch.stage -ceq 'COMPLETE' -and $report.failure -ceq 'ACCOUNT_PROBE_FAILED') 'child outcomes preserved before rejection'}
    if($scenario -in @('shortExhausted','mismatchExhausted','inputCancelled')){
        Check ($report.stage -ceq 'PASSWORD_CONFIRMATION' -and -not $report.createdAccount -and -not $report.createdDirectory -and -not $report.agentChanged) "password stage no changes $scenario"
        $expectedCode=if($scenario -ceq 'shortExhausted'){'ACCOUNT_PASSWORD_TOO_SHORT'}elseif($scenario -ceq 'mismatchExhausted'){'ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH'}else{'ACCOUNT_PASSWORD_INPUT_CANCELLED'}
        Check ($report.failure -ceq $expectedCode) "specific failure $scenario"
    }
    if($scenario -in @('shortExhausted','mismatchExhausted')){Check ($global:accountFixture.passwordReads -eq 6 -and $report.passwordAttempts.Count -eq 3) "three attempts only $scenario"}
    if($scenario -in @('shortThenSuccess','mismatchThenSuccess','thirdAttemptSuccess')){
        $expectedAttempts=if($scenario -ceq 'thirdAttemptSuccess'){3}else{2}
        Check ($report.passwordAttempts.Count -eq $expectedAttempts -and $report.passwordAttempts[-1].outcome -ceq 'CONFIRMED' -and $report.createdAccount) "recovery within same run $scenario"
    }
    if($scenario -ceq 'autoMember'){Check ($global:accountFixture.groupAdds -eq 0) 'existing standard membership not readded'}
    if($scenario -ceq 'agentFailure'){Check ($report.agentChanged -and $report.createdAccount -and $report.failureDetails.stage -ceq 'ENABLE_EXISTING_CLIENT_AGENT') 'partial change evidence'}
    if($scenario -ceq 'disable'){Check ($global:accountFixture.mutations -eq 1 -and -not $global:accountFixture.enabled) 'disable only owned account'}
}
Remove-Variable -Name accountFixture,realInventoryAssertion -Scope Global
Write-Host "PASS: $script:checks account assertions; $($scenarios.Count) mocked launcher workflows; native wrong-identity probe. No account/service/key/VPS changes. Fixtures: $temp"
