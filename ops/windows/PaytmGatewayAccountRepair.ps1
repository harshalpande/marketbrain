#Requires -Version 7.0
# Definitions only. Recovery is limited to the reviewed deleted-account inventory.
function Read-PaytmRepairJson([string]$Path,[int]$Limit=65536) {
    $null=Assert-PaytmAccountPath $Path
    $stream=[IO.File]::Open($Path,'Open','Read','Read')
    try{
        if($stream.Length -gt $Limit){throw 'ACCOUNT_REPAIR_JSON_SIZE'}
        $reader=[IO.StreamReader]::new($stream)
        try{
            $buffer=[char[]]::new($Limit+1);$count=$reader.ReadBlock($buffer,0,$buffer.Length)
            if($count -gt $Limit){throw 'ACCOUNT_REPAIR_JSON_SIZE'}
            $json=[string]::new($buffer,0,$count)
            if(-not $json.TrimStart().StartsWith('{')){throw 'ACCOUNT_REPAIR_JSON_SHAPE'}
            $json|ConvertFrom-Json -ErrorAction Stop
        }finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Read-PaytmReviewedRecovery([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)){throw 'ACCOUNT_REPAIR_REVIEWED_REPORT_REQUIRED'}
    $expected='06789E84490F9A524A5C920A433018288899FD33AE3B8A46761EC9DF3817B7FF'
    $null=Assert-PaytmAccountPath $Path
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $expected){throw 'ACCOUNT_REPAIR_REPORT_NOT_REVIEWED'}
    $r=Read-PaytmRepairJson $Path
    if($r.runId -cne 'ece79d9aa003448c99ae114f3d1c20ca' -or $r.status -cne 'INVENTORY_CAPTURED_RECOVERY_REVIEW_REQUIRED' -or
        $r.failureCount -ne 0 -or $null -ne $r.account -or $r.relation -cne 'ACCOUNT_ABSENT_MANIFEST_REMAINS'){
        throw 'ACCOUNT_REPAIR_REPORT_CONTRACT'
    }
    [pscustomobject]@{sourceHash=$expected;sourceRunId=$r.runId;oldSid=$r.manifest.sid;installationRunId=$r.manifest.runId}
}
function Assert-PaytmRepairAgent {
    $c=Get-PaytmAccountContract;$service=Get-Service ssh-agent -ErrorAction Stop
    $config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ssh-agent' -ErrorAction Stop
    if($service.Status -ne 'Running' -or $service.StartType -ne 'Automatic' -or
        ([string]$config.ImagePath).Trim('"') -ine $c.agentImage -or $config.ObjectName -ine 'LocalSystem'){
        throw 'ACCOUNT_REPAIR_AGENT_DRIFT'
    }
    if((Get-Service seclogon -ErrorAction Stop).StartType -eq 'Disabled'){throw 'ACCOUNT_SECONDARY_LOGON_DISABLED_NO_POLICY_CHANGE'}
}
function Assert-PaytmRepairManifestAcl($Acl,[string]$Sid) {
    if($Acl.AreAccessRulesProtected -or $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne 'S-1-5-32-544'){throw 'ACCOUNT_REPAIR_MANIFEST_ACL'}
    $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));$seen=@{}
    if($rules.Count -ne 3){throw 'ACCOUNT_REPAIR_MANIFEST_ACL'}
    foreach($rule in $rules){
        $id=$rule.IdentityReference.Value
        if($seen.ContainsKey($id) -or $id -cnotin @('S-1-5-18','S-1-5-32-544',$Sid)){throw 'ACCOUNT_REPAIR_MANIFEST_ACL'}
        $seen[$id]=$true
        $wanted=if($id -ceq $Sid){[int][Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[int][Security.AccessControl.FileSystemRights]::FullControl}
        $mask=-bnot [int][Security.AccessControl.FileSystemRights]::Synchronize
        if(-not $rule.IsInherited -or $rule.AccessControlType -ne 'Allow' -or $rule.InheritanceFlags -ne 'None' -or $rule.PropagationFlags -ne 'None' -or
            (([int]$rule.FileSystemRights -band $mask) -ne ($wanted -band $mask))){throw 'ACCOUNT_REPAIR_MANIFEST_ACL'}
    }
}
function Get-PaytmRepairArchivePath([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'ACCOUNT_REPAIR_RUN_INVALID'}
    (Get-PaytmAccountContract).root+'.recovery-'+$RunId
}
function Assert-PaytmRepairState($Approved,[string]$ArchivePath) {
    $c=Get-PaytmAccountContract
    $root=Assert-PaytmAccountPath $c.root;$null=Assert-PaytmAccountPath $ArchivePath
    if(Test-Path -LiteralPath $ArchivePath){throw 'ACCOUNT_REPAIR_ARCHIVE_EXISTS'}
    if(@(Get-LocalUser -ErrorAction Stop|Where-Object {$_.Name -ieq $c.name -or $_.SID.Value -ceq $Approved.oldSid}).Count){throw 'ACCOUNT_REPAIR_ACCOUNT_EXISTS'}
    $work=Join-Path $root 'work';$manifest=Join-Path $root 'installation.json'
    $null=Assert-PaytmAccountPath $work;$null=Assert-PaytmAccountPath $manifest
    if(-not (Get-Item -LiteralPath $root -Force).PSIsContainer -or -not (Get-Item -LiteralPath $work -Force).PSIsContainer -or (Get-Item -LiteralPath $manifest -Force).PSIsContainer){throw 'ACCOUNT_REPAIR_PATH_TYPE'}
    $entries=@(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop|Select-Object -First 3)
    if($entries.Count -ne 2 -or @($entries|Where-Object {$_.Name -cnotin @('work','installation.json')}).Count -or
        @(Get-ChildItem -LiteralPath $work -Force -ErrorAction Stop|Select-Object -First 1).Count){throw 'ACCOUNT_REPAIR_STORAGE_NOT_EMPTY_BASELINE'}
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $root) $Approved.oldSid
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $work) $Approved.oldSid -Writable
    Assert-PaytmRepairManifestAcl (Get-Acl -LiteralPath $manifest) $Approved.oldSid
    $saved=Read-PaytmRepairJson $manifest 8192
    if($saved.version -ne 1 -or $saved.name -cne $c.name -or $saved.root -cne $c.root -or $saved.sid -cne $Approved.oldSid -or
        $saved.runId -cne $Approved.installationRunId -or $saved.containsPrivateKey -isnot [bool] -or $saved.containsPrivateKey -ne $false -or
        $saved.previousAgentStatus -cne 'Stopped' -or $saved.previousAgentStartType -cne 'Disabled'){throw 'ACCOUNT_REPAIR_MANIFEST_DRIFT'}
    # The approved SID is bound to the hashed report, never arbitrary filter input.
    if(@(Get-CimInstance Win32_UserProfile -Filter ("SID='"+$Approved.oldSid+"'") -OperationTimeoutSec 10 -ErrorAction Stop).Count){throw 'ACCOUNT_REPAIR_OLD_PROFILE_EXISTS'}
    Assert-PaytmRepairAgent
    [pscustomobject]@{manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash}
}
function Move-PaytmRepairArchive([string]$ArchivePath,[string]$RunId) {
    $c=Get-PaytmAccountContract
    # Resolve both exact targets before the directory move. No glob, overwrite or recursive deletion.
    $source=Assert-PaytmAccountPath $c.root;$target=Assert-PaytmAccountPath $ArchivePath
    if($source -ine $c.root -or $target -cne (Get-PaytmRepairArchivePath $RunId) -or
        [IO.Path]::GetDirectoryName($source) -ine [IO.Path]::GetDirectoryName($target) -or (Test-Path -LiteralPath $target)){
        throw 'ACCOUNT_REPAIR_MOVE_TARGET_INVALID'
    }
    [IO.Directory]::Move($source,$target)
}
function Assert-PaytmRepairArchive([string]$ArchivePath,[string]$ManifestHash,[string]$OldSid) {
    $null=Assert-PaytmAccountPath $ArchivePath
    $manifest=Join-Path $ArchivePath 'installation.json';$null=Assert-PaytmAccountPath $manifest
    if(Test-Path -LiteralPath (Get-PaytmAccountContract).root){throw 'ACCOUNT_REPAIR_SOURCE_STILL_EXISTS'}
    if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -cne $ManifestHash){throw 'ACCOUNT_REPAIR_ARCHIVE_HASH_CHANGED'}
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $ArchivePath) $OldSid
    $work=Join-Path $ArchivePath 'work';$null=Assert-PaytmAccountPath $work
    Assert-PaytmAccountAcl (Get-Acl -LiteralPath $work) $OldSid -Writable
    Assert-PaytmRepairManifestAcl (Get-Acl -LiteralPath $manifest) $OldSid
}
