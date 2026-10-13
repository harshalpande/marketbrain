# Guarded file operations. Callers supply fresh server/route checks; no database writes here.
function Set-PaperHbaAclObject([string]$Path,$Acl,[switch]$Directory) {
    # Use SID-based .NET APIs, not Set-Acl's account-name resolution on domain-joined hosts.
    $null=Assert-PaperCustodyPath $Path
    if(([Management.Automation.PSTypeName]'System.IO.FileSystemAclExtensions').Type){
        if($Directory){[IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path),$Acl)}
        else{[IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Path),$Acl)}
    }elseif($Directory){[IO.Directory]::SetAccessControl($Path,$Acl)}else{[IO.File]::SetAccessControl($Path,$Acl)}
}
function Protect-PaperHbaBackupAcl([string]$Path,[switch]$Directory) {
    $acl=if($Directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
    $acl.SetAccessRuleProtection($true,$false)
    $inherit=if($Directory){[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'}else{[Security.AccessControl.InheritanceFlags]::None}
    foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18')){
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl',$inherit,'None','Allow'))
    }
    Set-PaperHbaAclObject $Path $acl -Directory:$Directory
    Assert-PaperPrivateAcl $Path
}
function Read-PaperHbaAcceptedPlan([string]$Path) {
    $full=Assert-PaperCustodyPath $Path
    if((Get-Item -LiteralPath $full).Length -gt 2MB){throw 'HBA_STAGE_EVIDENCE_SIZE'}
    $bytes=[IO.File]::ReadAllBytes($full)
    if((Get-PaperRestrictionHash $bytes) -cne 'C5D159FB8703627F2560BD139EF9AD00278197C52D4021B326C2C78C44B1FD64'){throw 'HBA_STAGE_EVIDENCE_HASH_MISMATCH'}
    $v=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json
    if($v.status -cne 'HBA_PLAN_CAPTURED_APPLY_BLOCKED' -or $v.failureCode -or -not $v.cleanupComplete){throw 'HBA_STAGE_PLAN_INCOMPLETE'}
    Assert-PaperHbaMetadata $v.metadata
    Assert-PaperHbaRoute $v.route $v.metadata $v.runId
    return $v
}
function Get-PaperHbaSddl([string]$Path) {
    $null=Assert-PaperCustodyPath $Path
    return (Get-Acl -LiteralPath $Path).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]'Owner,Group,Access')
}
function Read-PaperHbaBytes([string]$Path) {
    $null=Assert-PaperCustodyPath $Path
    $stream=[IO.File]::Open($Path,'Open','Read','Read')
    try {
        if($stream.Length -lt 1 -or $stream.Length -gt 1MB){throw 'HBA_STAGE_FILE_SIZE'}
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$n=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($n -eq 0){throw 'HBA_STAGE_TRUNCATED_FILE'};$offset+=$n}
        return ,$bytes
    }finally{$stream.Dispose()}
}
function Write-PaperHbaNewFile([string]$Path,[byte[]]$Bytes) {
    $null=Assert-PaperCustodyPath $Path
    $stream=[IO.File]::Open($Path,'CreateNew','Write','None')
    try {$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    Protect-PaperHbaBackupAcl $Path
}
function Assert-PaperHbaFileState([string]$Path,[string]$Hash,[string]$Sddl) {
    if((Get-PaperRestrictionHash (Read-PaperHbaBytes $Path)) -cne $Hash -or (Get-PaperHbaSddl $Path) -cne $Sddl){throw 'HBA_STAGE_FILE_OR_ACL_DRIFT'}
}
function New-PaperHbaBackup([string]$Target,$Plan,[string]$BackupRoot,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'HBA_STAGE_RUN_ID_INVALID'}
    $targetFull=Assert-PaperCustodyPath $Target
    $base=Assert-PaperCustodyPath $BackupRoot
    if([IO.Path]::GetPathRoot($base) -ine [IO.Path]::GetPathRoot($targetFull)){throw 'HBA_STAGE_SAME_VOLUME_REQUIRED'}
    if(-not(Test-Path -LiteralPath $base)){[void][IO.Directory]::CreateDirectory($base);Protect-PaperHbaBackupAcl $base -Directory}
    Assert-PaperPrivateAcl $base
    $dir=Join-Path $base $RunId
    if(Test-Path -LiteralPath $dir){throw 'HBA_STAGE_BACKUP_ALREADY_EXISTS'}
    [void][IO.Directory]::CreateDirectory($dir);Protect-PaperHbaBackupAcl $dir -Directory
    $original=Read-PaperHbaBytes $targetFull;$sddl=Get-PaperHbaSddl $targetFull
    if((Get-PaperRestrictionHash $original) -cne $Plan.originalHash -or (Get-PaperRestrictionHash ([Text.Encoding]::UTF8.GetBytes($sddl))) -cne $Plan.aclFingerprint){throw 'HBA_STAGE_FILE_OR_ACL_DRIFT'}
    $candidate=New-PaperRestrictionCandidate $original $Plan.originalHash
    if((Get-PaperRestrictionHash $candidate) -cne $Plan.candidateHash -or $candidate.Length -ne $Plan.candidateBytes){throw 'HBA_STAGE_CANDIDATE_MISMATCH'}
    Write-PaperHbaNewFile (Join-Path $dir 'original.bin') $original
    Write-PaperHbaNewFile (Join-Path $dir 'candidate.bin') $candidate
    $journal=[ordered]@{version='PAPER_HBA_BACKUP_V1';runId=$RunId;target=$targetFull;originalHash=$Plan.originalHash;candidateHash=$Plan.candidateHash;originalSddl=$sddl;aclFingerprint=$Plan.aclFingerprint;createdAtUtc=[DateTime]::UtcNow.ToString('o')}
    Write-PaperHbaNewFile (Join-Path $dir 'recovery.json') ([Text.Encoding]::UTF8.GetBytes(($journal|ConvertTo-Json -Compress)))
    # Journal and both independently re-read byte copies are durable before touching the target.
    $null=Read-PaperHbaBackup $dir
    Assert-PaperHbaFileState $targetFull $Plan.originalHash $sddl
    return $dir
}
function Read-PaperHbaBackup([string]$Directory) {
    $dir=Assert-PaperCustodyPath $Directory;Assert-PaperPrivateAcl $dir
    foreach($name in @('original.bin','candidate.bin','recovery.json')){$f=Assert-PaperCustodyPath (Join-Path $dir $name);Assert-PaperPrivateAcl $f;if((Get-Item -LiteralPath $f).Length -gt 1MB){throw 'HBA_STAGE_BACKUP_SIZE'}}
    $j=[IO.File]::ReadAllText((Join-Path $dir 'recovery.json'))|ConvertFrom-Json
    if($j.version -cne 'PAPER_HBA_BACKUP_V1' -or $j.runId -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFileName($dir) -cne $j.runId){throw 'HBA_STAGE_BACKUP_INVALID'}
    $null=Assert-PaperCustodyPath $j.target
    if([IO.Path]::GetFileName($j.target) -ine 'pg_hba.conf'){throw 'HBA_STAGE_TARGET_INVALID'}
    if((Get-PaperRestrictionHash (Read-PaperHbaBytes (Join-Path $dir 'original.bin'))) -cne $j.originalHash -or
       (Get-PaperRestrictionHash (Read-PaperHbaBytes (Join-Path $dir 'candidate.bin'))) -cne $j.candidateHash -or
       (Get-PaperRestrictionHash ([Text.Encoding]::UTF8.GetBytes($j.originalSddl))) -cne $j.aclFingerprint){throw 'HBA_STAGE_BACKUP_HASH_MISMATCH'}
    $rebuilt=New-PaperRestrictionCandidate (Read-PaperHbaBytes (Join-Path $dir 'original.bin')) $j.originalHash
    if((Get-PaperRestrictionHash $rebuilt) -cne $j.candidateHash){throw 'HBA_STAGE_BACKUP_INVALID'}
    return $j
}
function Set-PaperHbaFileFromBackup([string]$Directory,[switch]$Restore) {
    $j=Read-PaperHbaBackup $Directory
    $expected=if($Restore){$j.candidateHash}else{$j.originalHash}
    $desired=if($Restore){$j.originalHash}else{$j.candidateHash}
    $source=Join-Path $Directory $(if($Restore){'original.bin'}else{'candidate.bin'})
    Assert-PaperHbaFileState $j.target $expected $j.originalSddl
    # Same parent keeps inherited ACEs comparable to the original target.
    $temp=Join-Path ([IO.Path]::GetDirectoryName($j.target)) ('.mb-hba-replace-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try {
        Write-PaperHbaNewFile $temp (Read-PaperHbaBytes $source)
        $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetSecurityDescriptorSddlForm($j.originalSddl,[Security.AccessControl.AccessControlSections]'Owner,Group,Access')
        Set-PaperHbaAclObject $temp $acl
        Assert-PaperHbaFileState $temp $desired $j.originalSddl
        # Last check immediately before the same-volume replacement. No delete-then-move fallback.
        Assert-PaperHbaFileState $j.target $expected $j.originalSddl
        [IO.File]::Replace($temp,$j.target,[Management.Automation.Language.NullString]::Value,$false)
        Assert-PaperHbaFileState $j.target $desired $j.originalSddl
    }finally{if(Test-Path -LiteralPath $temp){$null=Assert-PaperCustodyPath $temp;Remove-Item -LiteralPath $temp}}
}
function Restore-PaperHbaBackup([string]$Directory) {
    $j=Read-PaperHbaBackup $Directory
    $current=Get-PaperRestrictionHash (Read-PaperHbaBytes $j.target)
    if($current -ceq $j.originalHash){Assert-PaperHbaFileState $j.target $j.originalHash $j.originalSddl;return 'ORIGINAL_ALREADY_PRESENT'}
    if($current -cne $j.candidateHash){throw 'HBA_STAGE_RECOVERY_OWNERSHIP_LOST'}
    # Unknown ACL changes also require review; never overwrite another administrator's edits.
    Set-PaperHbaFileFromBackup $Directory -Restore
    return 'ORIGINAL_RESTORED'
}
function Invoke-PaperHbaTransaction([string]$Directory,[scriptblock]$Validate,[System.Collections.IDictionary]$State) {
    $State.replacementAttempted=$true
    try {
        Set-PaperHbaFileFromBackup $Directory
        $State.hbaChanged=$true
        & $Validate
        $State.postValidationPassed=$true
    }catch {
        $originalFailure=$_
        try {$State.recoveryStatus=Restore-PaperHbaBackup $Directory;$State.rollbackFileVerified=$true}
        catch {$State.recoveryStatus='MANUAL_RECOVERY_REQUIRED'}
        throw $originalFailure
    }
}
