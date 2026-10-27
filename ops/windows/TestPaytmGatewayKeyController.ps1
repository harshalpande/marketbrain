#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "KEY_CONTROLLER_TEST_FAILED $Name"};$script:checks++}
# Reuse only fixture constructors, not the other test's execution or mocks.
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaytmGatewayKeyCustody.ps1'),[ref]$t,[ref]$e)
foreach($name in @('U32','SshString','Ascii','FixtureKey')){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$bytes=FixtureKey;$global:keyFixtureContract=Get-PaytmKeyContract
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-key-controller-'+[guid]::NewGuid().ToString('N'))
$fixtureScripts=Join-Path $temp 'repo\ops\windows';$null=New-Item -ItemType Directory -Path $fixtureScripts -Force
$mock=@'
function Assert-PaytmCustodyController {}
function Import-Module {param($Name,$ErrorAction)}
function Get-LocalUser {param($SID,$ErrorAction) [pscustomobject]@{Enabled=$true}}
function Read-PaytmOwnedAccount {if($global:keyFixture.case -ceq 'accountDrift'){throw 'ACCOUNT_OWNERSHIP_MISMATCH'};[pscustomobject]@{sid=$global:keyFixtureContract.accountSid;runId=$global:keyFixtureContract.accountRun}}
function Get-PaytmAccountContract {[pscustomobject]@{root=$global:keyFixture.app}}
function Get-PaytmKeyContract {$v=$global:keyFixtureContract.PSObject.Copy();$v.root=Join-Path $global:keyFixture.app 'key-custody';$v}
function Get-PaytmReadinessProgress {foreach($id in 1..6){[pscustomobject]@{id="G$id";percent=if($id -eq 1){100}elseif($id -eq 2){40}else{0}}}}
function Assert-PaytmRepairAgent {}
function Set-PaytmAccountDirectoryAcl($Path,$AccountSid) {}
function Set-PaytmPrivateKeyAcl($Path,$Sid) {if($global:keyFixture.case -ceq 'aclFailure'){throw 'KEY_STAGING_ACL_MISMATCH'}}
function Get-FileHash {param($LiteralPath,$Algorithm)
    if($LiteralPath -ceq $global:keyFixture.receipt){return [pscustomobject]@{Hash=if($global:keyFixture.case -ceq 'wrongReceipt'){'wrong'}else{'C4C78B0B4339E41A0CE17087D70F55D887440F7D93182E484AD115A0901F4912'}}}
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256
}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){$global:keyFixture.password=ConvertTo-SecureString 'FixtureOnly-NotARealPassword' -AsPlainText -Force;return $global:keyFixture.password}
    if($global:keyFixture.case -ceq 'cancel'){return 'CANCEL'};'IMPORT-GATEWAY-KEY'
}
function Invoke-PaytmAccountProbe($Sid,$RunId,$Password,$Diagnostics){
    if($global:keyFixture.case -ceq 'probeFailure'){throw 'ACCOUNT_PROBE_FAILED'}
    [pscustomobject]@{version=1;runId=$RunId;failure=$null;agentExit=1;sidMatched=$true;nonAdmin=$true;protectedWriteDenied=$true;workWriteReadDelete=$true;agentEmpty=$true}
}
function ConvertTo-PaytmPinnedHost($Text){
    if($global:keyFixture.case -ceq 'hostPinFailure'){throw 'KEY_HOST_PIN_MISMATCH'}
    [pscustomobject]@{knownHost='fixture public host';wrongHost='fixture negative public host';fingerprint=$global:keyFixtureContract.hostPin}
}
function Invoke-PaytmCustodyNative($Tool,[string[]]$Arguments,$Seconds){
    $global:keyFixture.nativeCalls+=@($Tool+' '+($Arguments -join ' '))
    if($Tool -ceq 'ssh-keyscan.exe'){
        if($global:keyFixture.case -ceq 'scanLaunchFailure'){throw 'KEY_NATIVE_START_FAILED'}
        if($global:keyFixture.case -cin @('hostScanFailure','hostScanTimeout')){
            return [pscustomobject]@{ExitCode=1;StoppedByRunner=($global:keyFixture.case -ceq 'hostScanTimeout');Stdout='';Stderr='fixture scan negotiation failure';ElapsedSeconds=5}
        }
    }
    $exit=if($Tool -ceq 'ssh-keyscan.exe'){0}elseif($global:keyFixture.case -ceq 'operatorHasKey'){0}else{1}
    [pscustomobject]@{ExitCode=$exit;StoppedByRunner=$false;Stdout='fixture';Stderr='';ElapsedSeconds=0}
}
function New-PaytmCustodyProcess {
    $p=[pscustomobject]@{StartInfo=$null;HasExited=$false;ExitCode=0}
    $p|Add-Member ScriptMethod Start {
        if($global:keyFixture.case -ceq 'startFailure'){throw 'KEY_WINDOW_START_FAILED'}
        $plan=Get-Content -Raw -LiteralPath (Join-Path (Get-PaytmKeyContract).root 'plan.json')|ConvertFrom-Json
        $global:keyFixture.run=$plan.runId
        $r=[ordered]@{version=1;runId=$plan.runId;stage='COMPLETE';identityVerified=$true;importAttempted=$true;imported=$true;revocationVerified=$true;reloadVerified=$true;wrongHostRejected=$true;pinnedAuthentication=$true;failure=$null}
        if($global:keyFixture.case -cin @('workerFailure','waitFailure')){$r.stage='IMPORT_SECOND';$r.failure='KEY_IMPORT_FAILED';$this.ExitCode=1}
        if($global:keyFixture.case -ceq 'badWorkerBinding'){$r.runId='wrong'}
        if($global:keyFixture.case -cne 'missingWorkerReport'){
            [IO.File]::WriteAllText((Join-Path $global:keyFixture.app ('work\key-custody-'+$plan.runId+'.json')),($r|ConvertTo-Json))
        }
        $true
    }
    $p|Add-Member ScriptMethod WaitForExit {param($Timeout)
        if($global:keyFixture.case -ceq 'waitFailure' -and -not $this.HasExited){throw 'KEY_WINDOW_TIMEOUT'}
        $this.HasExited=$true;$true
    }
    $p|Add-Member ScriptMethod Kill {param($Tree) $global:keyFixture.kills++;$this.HasExited=$true}
    $p|Add-Member ScriptMethod Dispose {}
    $p
}
function Invoke-PaytmAccountProbeProcess($Info,$Source,$Diagnostics){
    [pscustomobject]@{runId=$global:keyFixture.run;identityVerified=$true;agentIdentityVerified=$true;signingVerified=$true;failure=if($global:keyFixture.case -ceq 'freshFailure'){'KEY_FRESH_PROCESS_FAILED'}else{$null}}
}
'@
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmTunnelVerification.ps1','PaytmGatewayKeyWorker.ps1','InstallPaytmGatewayKeyCustody.ps1','GetPaytmHostScanDiagnostic.ps1')){
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
    if($name -ceq 'PaytmGatewayKeyCustody.ps1'){$source+="`n"+$mock}
    [IO.File]::WriteAllText((Join-Path $fixtureScripts $name),$source)
}
$scenarios=@('pass','cancel','wrongReceipt','accountDrift','probeFailure','hostPinFailure','hostScanFailure','hostScanTimeout','aclFailure','operatorHasKey','startFailure','workerFailure','waitFailure','badWorkerBinding','missingWorkerReport','freshFailure')
foreach($case in $scenarios){
    $caseRoot=Join-Path $temp $case;$app=Join-Path $caseRoot 'app';$null=New-Item -ItemType Directory -Path (Join-Path $app 'work') -Force
    $inputKey=Join-Path $caseRoot 'fixture.openssh';[IO.File]::WriteAllBytes($inputKey,$bytes)
    $receipt=Join-Path $caseRoot 'accepted.json';[IO.File]::WriteAllText($receipt,'{}')
    $global:keyFixture=@{case=$case;app=$app;receipt=$receipt;password=$null;nativeCalls=@();kills=0;run=$null}
    $output=Join-Path $caseRoot 'output';$failed=$false;$console=@()
    try{$console=@(& (Join-Path $fixtureScripts 'InstallPaytmGatewayKeyCustody.ps1') -EncryptedKeyPath $inputKey -AccountReportPath $receipt -OutputDirectory $output 6>&1)}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) ('one evidence '+$case)
    $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
    Check ($failed -eq ($case -cne 'pass')) ('controller result '+$case+' '+$r.failure+' '+($r.failureDetails|ConvertTo-Json -Compress))
    Check ($raw -notmatch 'FixtureOnly|BEGIN OPENSSH PRIVATE KEY' -and ($console -join '') -notmatch 'FixtureOnly') 'no private material/password in evidence'
    Check (-not $r.ordersEnabled -and -not $r.serviceConfigurationChanged -and -not $r.tunnelStarted -and -not $r.taskInstalled) 'authority unchanged'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($inputKey)) -ceq [Convert]::ToBase64String($bytes)) 'original encrypted input preserved'
    if($null -ne $global:keyFixture.password){$disposed=$false;try{$copy=$global:keyFixture.password.Copy();$copy.Dispose()}catch{$disposed=$true};Check $disposed 'Windows password disposed'}
    if($case -ceq 'pass'){Check ($r.stagedEncryptedCopyRemoved -and $r.operatorSigningDeniedAfter -and $r.freshProcess.signingVerified -and $r.candidateGroup2PercentIfReviewed -eq 60) 'pass includes copy removal and fresh process';Check (-not (Test-Path -LiteralPath (Join-Path $app 'key-custody\gateway.openssh'))) 'no staged encrypted private file after success'}
    if($case -cin @('cancel','wrongReceipt','accountDrift','probeFailure','hostPinFailure','hostScanFailure','hostScanTimeout')){Check (-not $r.stagingCreated) 'stop before staging'}
    if($case -cin @('hostScanFailure','hostScanTimeout')){
        Check ($r.failure -ceq 'KEY_HOST_SCAN_FAILED' -and $r.hostScan.stderr -ceq 'fixture scan negotiation failure' -and $r.hostScan.exitCode -eq 1) 'native scan cause checkpointed before throw'
        Check ($r.hostScan.stoppedByRunner -eq ($case -ceq 'hostScanTimeout')) 'timeout distinguished from native exit'
        Check (-not (($console -join '') -match 'A key may already be loaded')) 'no misleading import warning before staging'
    }
    if($case -cin @('aclFailure','operatorHasKey','startFailure','workerFailure','waitFailure','badWorkerBinding','missingWorkerReport')){Check (Test-Path -LiteralPath (Join-Path $app 'key-custody\gateway.openssh')) 'partial encrypted staging retained'}
    if($case -ceq 'waitFailure'){Check ($global:keyFixture.kills -eq 1 -and $r.windowStopConfirmed -and $null -ne $r.worker) 'owned process cleanup and partial evidence'}
    if($case -ceq 'freshFailure'){Check ($r.stagedEncryptedCopyRemoved -and $r.worker.imported -and $null -ne $r.freshProcess.failure) 'later failure does not erase import history'}
}
Write-Host "PASS: $script:checks controller assertions; $($scenarios.Count) mocked full installer workflows. Only synthetic temp files changed; no user/service/ACL/agent/network mutation."
$before=$script:checks
foreach($case in @('pass','hostScanFailure','hostScanTimeout','hostPinFailure','scanLaunchFailure')){
    $global:keyFixture=@{case=$case;nativeCalls=@();app=(Join-Path $temp 'unused-diagnostic-app')};$output=Join-Path $temp ('diagnostic-'+$case)
    $null=& (Join-Path $fixtureScripts 'GetPaytmHostScanDiagnostic.ps1') -OutputDirectory $output 6>&1
    $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) 'diagnostic one JSON'
    $r=Get-Content -Raw -LiteralPath $files[0].FullName|ConvertFrom-Json
    Check ($r.hostPinVerified -eq ($case -ceq 'pass')) 'diagnostic pin result'
    Check (-not $r.keyRead -and -not $r.keyImported -and -not $r.authenticated -and -not $r.accountChanged -and -not $r.serviceChanged -and -not $r.ordersEnabled) 'diagnostic read-only boundary'
    Check ($global:keyFixture.nativeCalls.Count -eq 2 -and $global:keyFixture.nativeCalls[0] -ceq 'ssh.exe -V' -and $global:keyFixture.nativeCalls[1] -ceq 'ssh-keyscan.exe -v -4 -T 5 -t rsa 130.250.191.137') 'diagnostic fixed version and scan only'
    if($case -cin @('hostScanFailure','hostScanTimeout')){Check ($r.hostScan.stderr -ceq 'fixture scan negotiation failure') 'diagnostic retains native cause'}
    if($case -ceq 'hostPinFailure'){Check ($r.failure -ceq 'KEY_HOST_PIN_MISMATCH') 'never trust changed pin'}
    if($case -ceq 'scanLaunchFailure'){Check ($r.failure -ceq 'KEY_NATIVE_START_FAILED' -and $null -eq $r.hostScan) 'launch failure still produces report'}
}
$bounded=Get-PaytmHostScanEvidence ([pscustomobject]@{ExitCode=1;StoppedByRunner=$false;ElapsedSeconds=1;Stdout=('a'*9000);Stderr=('b'*9000)})
Check ($bounded.outputTruncated -and $bounded.stdout.Length -eq 8192 -and $bounded.stderr.Length -eq 8192) 'bounded diagnostic output'
Write-Host "PASS: $($script:checks-$before) diagnostic assertions; five mocked diagnostic workflows; no real network contact."
