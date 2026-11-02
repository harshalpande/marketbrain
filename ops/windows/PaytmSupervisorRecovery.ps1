#Requires -Version 7.0
# Scoped recovery of the reviewed E206 installation failure; no registration or credentials.
function Assert-PaytmSupervisorFailureReceipt([string]$Path) {
    $null=Assert-PaytmAccountPath $Path
    if((Get-FileHash -LiteralPath $Path).Hash -cne 'C4422FE831E1BAFEE49932335B96CFFEA57F741647C87288E3E3F43BC6CA9CD8'){throw 'HOST_RECOVERY_RECEIPT_NOT_REVIEWED'}
    $r=Read-PaytmRepairJson $Path 32768
    if($r.runId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $r.failure -cne 'HOST_TASK_LAUNCH_FAILED' -or $r.taskInfo.lastTaskResult -ne 1 -or $null -ne $r.cleanupFailure -or -not $r.taskRegistered -or $null -ne $r.first){throw 'HOST_RECOVERY_RECEIPT_INVALID'}
    $r
}
function Assert-PaytmRecoverableHost($Receipt) {
    $c=Get-PaytmHostContract;$sid=(Get-PaytmKeyContract).accountSid
    foreach($p in @($c.root,$c.work)){
        $null=Assert-PaytmAccountPath $p;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $p) $sid -Writable:($p -ceq $c.work)
    }
    $task=Get-PaytmOwnedHostTask $Receipt.runId $false
    if([string]$task.State -cin @('Running','Queued')){throw 'HOST_RECOVERY_TASK_NOT_STOPPED'}
    $manifest=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.root 'manifest.json'))
    if($manifest.version -ne 1 -or $manifest.installationId -cne $Receipt.runId){throw 'HOST_RECOVERY_MANIFEST_DRIFT'}
    foreach($name in @('host.ps1','runner.ps1','native.dll')){
        $p=Assert-PaytmAccountPath (Join-Path $c.root $name)
        if((Get-FileHash -LiteralPath $p).Hash -cne $manifest.hashes.$name){throw 'HOST_RECOVERY_INSTALLED_HASH_DRIFT'}
    }
    if($manifest.hashes.'runner.ps1' -cne $Receipt.sourceHashes.'RunPaytmGatewaySupervisor.ps1' -or
       $manifest.hashes.'host.ps1' -cne $Receipt.sourceHashes.'PaytmSupervisorHost.ps1' -or
       (Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root 'native.cs'))).Hash -cne $Receipt.sourceHashes.'PaytmSupervisorNative.cs'){throw 'HOST_RECOVERY_SOURCE_NOT_REVIEWED'}
    $control=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.root 'control.json'))
    Assert-PaytmHostControl $control $Receipt.runId
    if($control.mode -cne 'STOP'){throw 'HOST_RECOVERY_STOP_REQUIRED'}
    foreach($name in @('status.json','blocked.json','startup-failure.json')){
        $p=Assert-PaytmAccountPath (Join-Path $c.work $name)
        if(Test-Path -LiteralPath $p){throw 'HOST_RECOVERY_UNREVIEWED_WORKER_EVIDENCE'}
    }
    $manifest
}
function Update-PaytmReviewedRunner($Manifest,[string]$RecoveryRun,[string]$SourceDirectory,$Report) {
    if($RecoveryRun -cnotmatch '^[a-f0-9]{32}$'){throw 'HOST_RECOVERY_RUN_INVALID'}
    $c=Get-PaytmHostContract
    $backup=Join-Path $c.root ('recovery-'+$RecoveryRun)
    $null=Assert-PaytmAccountPath $backup
    if(Test-Path -LiteralPath $backup){throw 'HOST_RECOVERY_BACKUP_EXISTS'}
    $null=New-Item -ItemType Directory -Path $backup
    Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
    foreach($name in @('runner.ps1','manifest.json')){
        Copy-Item -LiteralPath (Join-Path $c.root $name) -Destination (Join-Path $backup $name)
        if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $c.root $name)).Hash){throw 'HOST_RECOVERY_BACKUP_MISMATCH'}
    }
    $Report.backupCreated=$true;$Report.oldRunnerHash=$Manifest.hashes.'runner.ps1'
    $replacement=Join-Path $c.root ('runner-'+$RecoveryRun+'.tmp')
    $source=Join-Path $SourceDirectory 'RunPaytmGatewaySupervisor.ps1'
    $Report.newRunnerHash=(Get-FileHash -LiteralPath $source).Hash
    $bytes=[IO.File]::ReadAllBytes($source)
    if($bytes.Length -gt 32768){throw 'HOST_RECOVERY_RUNNER_SIZE'}
    $file=[IO.File]::Open($replacement,'CreateNew','Write','None')
    try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
    if((Get-FileHash -LiteralPath $replacement).Hash -cne $Report.newRunnerHash){throw 'HOST_RECOVERY_REPLACEMENT_DRIFT'}
    [IO.File]::Replace($replacement,(Join-Path $c.root 'runner.ps1'),[Management.Automation.Language.NullString]::Value)
    $Report.runnerUpdated=$true
    $Manifest.hashes.'runner.ps1'=$Report.newRunnerHash
    Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $Manifest
    if((Get-FileHash -LiteralPath (Join-Path $c.root 'runner.ps1')).Hash -cne $Report.newRunnerHash){throw 'HOST_RECOVERY_UPDATE_MISMATCH'}
    $Report.manifestUpdated=$true
}
