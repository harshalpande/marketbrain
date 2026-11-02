#Requires -Version 5.1
[CmdletBinding()]param([switch]$AsObject)
$ErrorActionPreference='Stop'
foreach($name in @('PaytmSupervisorHost.ps1','PaytmSupervisorRecovery.ps1')){. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-recovery-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$script:caseRoot=$null;$script:taskRunning=$false;$script:aclFailure=$false;$count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "RECOVERY_TEST_$Name"};$script:count++}
function Reject([scriptblock]$Body,[string]$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
# Only OS-specific task and ACL APIs are mocked. File hashes, backup, atomic replacement and guards are real.
function Get-PaytmHostContract {[pscustomobject]@{root=$script:caseRoot;work=(Join-Path $script:caseRoot 'work')}}
function Get-PaytmKeyContract {[pscustomobject]@{accountSid='S-1-5-21-1-2-3-1010'}}
function Assert-PaytmAccountPath($Path){[IO.Path]::GetFullPath($Path)}
function Assert-PaytmAccountAcl {if($script:aclFailure){throw 'MOCK_ACL_DRIFT'}}
function Set-PaytmAccountDirectoryAcl {}
function Get-PaytmOwnedHostTask {[pscustomobject]@{State=if($script:taskRunning){'Running'}else{'Disabled'}}}
try {
    $script:caseRoot=Join-Path $temp 'installed';$null=New-Item -ItemType Directory -Path $script:caseRoot
    $work=Join-Path $script:caseRoot 'work';$null=New-Item -ItemType Directory -Path $work
    $source=Join-Path $temp 'source';$null=New-Item -ItemType Directory -Path $source
    foreach($n in @('runner.ps1','host.ps1','native.dll','native.cs')){[IO.File]::WriteAllText((Join-Path $script:caseRoot $n),('original '+$n))}
    [IO.File]::WriteAllText((Join-Path $source 'RunPaytmGatewaySupervisor.ps1'),'corrected runner')
    $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
    foreach($n in @('runner.ps1','host.ps1','native.dll')){$hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $script:caseRoot $n)).Hash}
    $manifest=[pscustomobject]@{version=1;installationId=$id;hashes=[pscustomobject]$hashes}
    $receipt=[pscustomobject]@{runId=$id;sourceHashes=[pscustomobject]@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmSupervisorHost.ps1'=$hashes['host.ps1'];'PaytmSupervisorNative.cs'=(Get-FileHash -LiteralPath (Join-Path $script:caseRoot 'native.cs')).Hash}}
    $manifestPath=Join-Path $script:caseRoot 'manifest.json';$controlPath=Join-Path $script:caseRoot 'control.json'
    Write-PaytmHostJson $manifestPath $manifest
    Write-PaytmHostJson $controlPath @{version=1;installationId=$id;mode='STOP'}
    $accepted=Assert-PaytmRecoverableHost $receipt
    Check ($accepted.installationId -ceq $id) 'VALID_RETAINED_INSTALL'
    $script:taskRunning=$true;Reject {Assert-PaytmRecoverableHost $receipt} 'RUNNING_TASK_BLOCKS';$script:taskRunning=$false
    $script:aclFailure=$true;Reject {Assert-PaytmRecoverableHost $receipt} 'ACL_DRIFT_BLOCKS';$script:aclFailure=$false
    Write-PaytmHostJson $controlPath @{version=1;installationId=$id;mode='LOCKED'}
    Reject {Assert-PaytmRecoverableHost $receipt} 'STOP_REQUIRED'
    Write-PaytmHostJson $controlPath @{version=1;installationId=$id;mode='STOP'}
    foreach($name in @('status.json','blocked.json','startup-failure.json')){
        $p=Join-Path $work $name;[IO.File]::WriteAllText($p,'{}')
        Reject {Assert-PaytmRecoverableHost $receipt} 'UNREVIEWED_WORKER_BLOCKS';Remove-Item -LiteralPath $p
    }
    $manifest.installationId='b'*32;Write-PaytmHostJson $manifestPath $manifest
    Reject {Assert-PaytmRecoverableHost $receipt} 'WRONG_INSTALL_BLOCKS'
    $manifest.installationId=$id;Write-PaytmHostJson $manifestPath $manifest
    $manifest.hashes.'native.dll'='0'*64;Write-PaytmHostJson $manifestPath $manifest
    Reject {Assert-PaytmRecoverableHost $receipt} 'DLL_DRIFT_BLOCKS'
    $manifest.hashes.'native.dll'=(Get-FileHash -LiteralPath (Join-Path $script:caseRoot 'native.dll')).Hash;Write-PaytmHostJson $manifestPath $manifest
    $receipt.sourceHashes.'RunPaytmGatewaySupervisor.ps1'='0'*64
    Reject {Assert-PaytmRecoverableHost $receipt} 'UNREVIEWED_RUNNER_BLOCKS'
    $receipt.sourceHashes.'RunPaytmGatewaySupervisor.ps1'=$manifest.hashes.'runner.ps1'
    $beforeManifest=[IO.File]::ReadAllText($manifestPath);$beforeRunner=[IO.File]::ReadAllText((Join-Path $script:caseRoot 'runner.ps1'))
    $report=@{};$recovery='c'*32
    Update-PaytmReviewedRunner $manifest $recovery $source $report
    Check ($report.backupCreated -and $report.runnerUpdated -and $report.manifestUpdated) 'UPDATE_COMPLETED'
    $backup=Join-Path $script:caseRoot ('recovery-'+$recovery)
    Check ([IO.File]::ReadAllText((Join-Path $backup 'runner.ps1')) -ceq $beforeRunner) 'RUNNER_BACKUP_EXACT'
    Check ([IO.File]::ReadAllText((Join-Path $backup 'manifest.json')) -ceq $beforeManifest) 'MANIFEST_BACKUP_EXACT'
    Check ([IO.File]::ReadAllText((Join-Path $script:caseRoot 'runner.ps1')) -ceq 'corrected runner') 'RUNNER_REPLACED'
    $saved=Read-PaytmHostJson $manifestPath
    Check ($saved.hashes.'runner.ps1' -ceq $report.newRunnerHash -and $saved.hashes.'native.dll' -ceq $hashes['native.dll'] -and $saved.hashes.'host.ps1' -ceq $hashes['host.ps1']) 'ONLY_RUNNER_HASH_CHANGED'
    Check ((Read-PaytmHostJson $controlPath).mode -ceq 'STOP') 'UPDATE_DOES_NOT_ACTIVATE'
    Reject {Update-PaytmReviewedRunner $manifest $recovery $source @{}} 'BACKUP_COLLISION_BLOCKS'
    Reject {Assert-PaytmRecoverableHost $receipt} 'SECOND_REPAIR_BLOCKS'
    Reject {Assert-PaytmSupervisorFailureReceipt $manifestPath} 'UNREVIEWED_RECEIPT_BLOCKS'
    $summary=[pscustomobject]@{status='RECOVERY_GUARDS_PASSED';assertions=$count;taskAndAclApisMocked=$true;realFileBackupAndUpdate=$true;taskRegistered=$false;networkContacted=$false}
    if($AsObject){$summary}else{$summary|ConvertTo-Json}
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'mb-recovery-tests-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
