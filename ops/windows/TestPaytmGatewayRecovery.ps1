#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'GetPaytmGatewayAccountRecovery.ps1') -LibraryOnly
$checks=0
function Check([bool]$Value){if(-not $Value){throw 'RECOVERY_TEST_FAILED'};$script:checks++}
function Reject([scriptblock]$Action){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed}
$c=Get-PaytmAccountContract
$valid=[pscustomobject]@{version=1;name=$c.name;root=$c.root;sid='S-1-5-21-111-222-333-1001';runId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';previousAgentStatus='Stopped';previousAgentStartType='Disabled';containsPrivateKey=$false;extraSecret='FixtureOnly-DO-NOT-EXPORT'}
$safe=ConvertTo-PaytmRecoveryManifest $valid
Check (($safe|ConvertTo-Json) -notmatch 'FixtureOnly')
Check ((Get-PaytmRecoveryRelation $null $safe) -ceq 'ACCOUNT_ABSENT_MANIFEST_REMAINS')
Check ((Get-PaytmRecoveryRelation $null $null) -ceq 'MANIFEST_UNAVAILABLE_REVIEW_REQUIRED')
Check ((Get-PaytmRecoveryRelation ([pscustomobject]@{sid=$safe.sid}) $safe) -ceq 'ACCOUNT_AND_MANIFEST_SID_MATCH_REVIEW_REQUIRED')
Check ((Get-PaytmRecoveryRelation ([pscustomobject]@{sid='S-1-5-21-111-222-333-1002'}) $safe) -ceq 'ACCOUNT_NAME_REUSED_DIFFERENT_SID')
foreach($field in @('version','name','root','sid','runId','previousAgentStatus','previousAgentStartType','containsPrivateKey')){
    $bad=$valid.PSObject.Copy();$bad.$field='invalid';Reject {ConvertTo-PaytmRecoveryManifest $bad}
}
Reject {ConvertTo-PaytmRecoveryManifest $null}
Reject {ConvertTo-PaytmRecoveryManifest @($valid,$valid)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-recovery-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$file=Join-Path $temp 'installation.json'
[IO.File]::WriteAllText($file,($valid|ConvertTo-Json))
Check ((Read-PaytmRecoveryManifest $file).sid -ceq $safe.sid)
Check ((Get-PaytmRecoveryPath $file $false).exists)
Check ((Get-PaytmRecoveryPath $temp $true).immediateEntriesObserved -eq 1)
Check (-not (Get-PaytmRecoveryPath (Join-Path $temp 'absent') $true).exists)
Reject {Get-PaytmRecoveryPath $file $true}
[IO.File]::WriteAllText((Join-Path $temp 'bad.json'),'not-json')
Reject {Read-PaytmRecoveryManifest (Join-Path $temp 'bad.json')}
[IO.File]::WriteAllText((Join-Path $temp 'big.json'),('x'*8193))
Reject {Read-PaytmRecoveryManifest (Join-Path $temp 'big.json')}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'GetPaytmGatewayAccountRecovery.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0)
$commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()})
foreach($forbidden in @('New-LocalUser','Remove-LocalUser','Enable-LocalUser','Disable-LocalUser','Set-Service','Start-Service','Stop-Service','Set-Acl','Remove-Item','Move-Item','Invoke-PaytmAccountProbe')){Check ($forbidden -cnotin $commands)}
Write-Host "PASS: $checks recovery checks; only synthetic temp fixtures written. No account/service/permission changes."
