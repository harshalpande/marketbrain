#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1')
$script:checks=0
function Check([bool]$Value){if(-not $Value){throw 'REPAIR_TEST_FAILED'};$script:checks++}
function Reject([scriptblock]$Action){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed}
$sid='S-1-5-21-111-222-333-1001';$run='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-repair-tests-'+[guid]::NewGuid().ToString('N'))
$script:root=Join-Path $temp 'Gateway';$null=New-Item -ItemType Directory -Path (Join-Path $script:root 'work') -Force
function Get-PaytmAccountContract {[pscustomobject]@{root=$script:root;name='marketbrain-gateway';agentImage='C:\Windows\System32\OpenSSH\ssh-agent.exe'}}
$approved=[pscustomobject]@{oldSid=$sid;installationRunId=$run}
$manifest=Join-Path $script:root 'installation.json'
$valid=[ordered]@{version=1;name='marketbrain-gateway';root=$script:root;sid=$sid;runId=$run;containsPrivateKey=$false;previousAgentStatus='Stopped';previousAgentStartType='Disabled'}
[IO.File]::WriteAllText($manifest,($valid|ConvertTo-Json))
$script:fixture=@{account=$false;profile=$false;agent='Running';image='C:\Windows\System32\OpenSSH\ssh-agent.exe';badAcl=$false;profileThrows=$false}
function Get-LocalUser {param($ErrorAction) if($script:fixture.account){[pscustomobject]@{Name='marketbrain-gateway';SID=[pscustomobject]@{Value=$sid}}}}
function Get-CimInstance {param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction) if($script:fixture.profileThrows){throw 'fixture query failure'};if($script:fixture.profile){[pscustomobject]@{SID=$sid}}}
function Get-Service {param($Name,$ErrorAction) [pscustomobject]@{Status=$script:fixture.agent;StartType=if($Name -eq 'seclogon'){'Manual'}else{'Automatic'}}}
function Get-ItemProperty {param($LiteralPath,$ErrorAction) [pscustomobject]@{ImagePath=$script:fixture.image;ObjectName='LocalSystem'}}
function New-FixtureManifestAcl {
    $acl=[Security.AccessControl.FileSecurity]::new()
    $acl.SetSecurityDescriptorSddlForm(('O:BAG:BAD:AI(A;ID;FA;;;SY)(A;ID;FA;;;BA)(A;ID;0x1200a9;;;'+$sid+')'))
    $acl
}
function Get-Acl {param($LiteralPath)
    if($script:fixture.badAcl){return New-PaytmAccountAcl 'S-1-5-21-111-222-333-1002'}
    if([IO.Path]::GetFileName($LiteralPath) -eq 'installation.json'){return New-FixtureManifestAcl}
    New-PaytmAccountAcl $sid -Writable:([IO.Path]::GetFileName($LiteralPath) -eq 'work')
}
$archive=Get-PaytmRepairArchivePath $run
$state=Assert-PaytmRepairState $approved $archive
Check ($state.manifestHash -ceq (Get-FileHash -LiteralPath $manifest).Hash)
foreach($case in @('account','profile','badAcl','profileThrows')){
    $script:fixture[$case]=$true;Reject {Assert-PaytmRepairState $approved $archive};$script:fixture[$case]=$false
}
$script:fixture.agent='Stopped';Reject {Assert-PaytmRepairState $approved $archive};$script:fixture.agent='Running'
$script:fixture.image='C:\unexpected.exe';Reject {Assert-PaytmRepairState $approved $archive};$script:fixture.image='C:\Windows\System32\OpenSSH\ssh-agent.exe'
$extra=Join-Path $script:root 'unexpected.txt';[IO.File]::WriteAllText($extra,'fixture')
Reject {Assert-PaytmRepairState $approved $archive}
# Move only the owned fixture out of the exact fixture root; retain it for inspection.
[IO.File]::Move($extra,(Join-Path $temp 'unexpected.txt'))
$extra=Join-Path $script:root 'work\leftover.txt';[IO.File]::WriteAllText($extra,'fixture')
Reject {Assert-PaytmRepairState $approved $archive}
[IO.File]::Move($extra,(Join-Path $temp 'leftover.txt'))
$valid.sid='S-1-5-21-111-222-333-1002';[IO.File]::WriteAllText($manifest,($valid|ConvertTo-Json))
Reject {Assert-PaytmRepairState $approved $archive}
$valid.sid=$sid;[IO.File]::WriteAllText($manifest,($valid|ConvertTo-Json))
Reject {Get-PaytmRepairArchivePath '../bad'}
Reject {Move-PaytmRepairArchive (Join-Path $temp 'unreviewed') $run}
$null=New-Item -ItemType Directory -Path $archive
Reject {Assert-PaytmRepairState $approved $archive}
Reject {Move-PaytmRepairArchive $archive $run}
# Preserve that collision fixture, then exercise actual same-directory rename without overwrite.
[IO.Directory]::Move($archive,(Join-Path $temp 'collision-preserved'))
Move-PaytmRepairArchive $archive $run
Check (-not (Test-Path -LiteralPath $script:root) -and (Test-Path -LiteralPath $archive))
Assert-PaytmRepairArchive $archive $state.manifestHash $sid;$script:checks++
Reject {Assert-PaytmRepairArchive $archive ('0'*64) $sid}
Reject {Read-PaytmReviewedRecovery (Join-Path $archive 'installation.json')}
Reject {Read-PaytmReviewedRecovery ''}
Reject {Read-PaytmRepairJson (Join-Path $archive 'installation.json') 10}
$acl=New-FixtureManifestAcl;Assert-PaytmRepairManifestAcl $acl $sid;$script:checks++
$acl.SetAccessRuleProtection($true,$true);Reject {Assert-PaytmRepairManifestAcl $acl $sid}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0)
$commands=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()})
foreach($blocked in @('Remove-Item','Remove-LocalUser','Set-Service','Stop-Service','Start-Service','Set-Acl')){Check ($blocked -cnotin $commands)}
Write-Host "PASS: $script:checks repair checks; native rename/hash preservation in owned temp fixtures; Windows identity/service/ACL queries mocked. No real account or service changes."
