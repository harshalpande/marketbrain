# Offline only: generated files/ACLs; PostgreSQL, Docker, prompts and credentials mocked.
param([string]$OutputDirectory=(Join-Path ([IO.Path]::GetTempPath()) 'MarketBrainRehearsalReports'))
$ErrorActionPreference='Stop'
foreach($file in @('NumericalHistoryEvidence.ps1','PaperWriterCustody.ps1','PaperWriterRestriction.ps1','PaperWriterAccessReview.ps1','PaperWriterHbaPlan.ps1','PaperWriterHbaStage.ps1')){. (Join-Path $PSScriptRoot $file)}
$timer=[Diagnostics.Stopwatch]::StartNew()
$reportRoot=Assert-PaperCustodyPath $OutputDirectory
[void][IO.Directory]::CreateDirectory($reportRoot)
$reportPath=Join-Path $reportRoot ('paper-hba-rehearsal-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
$rehearsal=[ordered]@{status='RUNNING';powerShell=$PSVersionTable.PSVersion.ToString();runtime=[Environment]::Version.ToString();phase='SYNTHETIC_BACKUP_AND_REPLACEMENT';assertionsPassed=0;elapsedSeconds=0;failureCode=$null;failureLine=$null;fileState=$null;fixtureCleanupComplete=$false;databaseContacted=$false;realHbaChanged=$false;actionExecutionEnabled=$false;sourceHashes=@{}}
foreach($source in @('PaperWriterHbaStage.ps1','TestPaperWriterHbaStage.ps1','TestPaperHbaAclComparison.ps1','SetPaperWriterHbaRestriction.ps1','RestorePaperWriterHbaRestriction.ps1')){$rehearsal.sourceHashes[$source]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $source) -Algorithm SHA256).Hash}
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw $Name};$script:checks++}
function Denied([scriptblock]$Action,[string]$Code){$caught=$null;try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Check ($caught -ceq $Code) ('Expected '+$Code+' got '+$caught)}
try {
$rehearsal['aclComparison']=& (Join-Path $PSScriptRoot 'TestPaperHbaAclComparison.ps1')
Check ($rehearsal.aclComparison.status -ceq 'PASSED') 'Pure security descriptor regression suite'
Write-Progress -Activity 'Generated-file HBA rehearsal' -Status 'File replacement and permission checks' -PercentComplete 0
Write-Host '[0%] Generated files only. Testing backup, replacement and exact permission preservation.'
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-hba-stage-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($work)
# Test-only legacy descriptor writer. Never imported by production scripts.
if(-not ('MarketBrainHbaFixtureNative' -as [type])){
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class MarketBrainHbaFixtureNative {
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetFileSecurity(string name, uint info, byte[] descriptor);
}
'@
}
function Set-FixtureDacl([string]$Path,[string]$Sddl){
    $full=Assert-PaperCustodyPath $Path
    if(-not $full.StartsWith(($work+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture path escaped generated workspace'}
    $descriptor=[Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    if(([int]$descriptor.ControlFlags -band 1024) -ne 0){
        $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetSecurityDescriptorSddlForm($Sddl,[Security.AccessControl.AccessControlSections]'Owner,Group,Access')
        Set-PaperHbaAclObject $full $acl
        return
    }
    $binary=New-Object byte[] $descriptor.BinaryLength;$descriptor.GetBinaryForm($binary,0)
    if(-not [MarketBrainHbaFixtureNative]::SetFileSecurity($full,4,$binary)){throw 'Fixture DACL setup failed'}
}
$hba=Join-Path $work 'pg_hba.conf';$backupRoot=Join-Path $work 'backups';$psqlPath=Join-Path $work 'psql.exe'
$bytes=[Text.Encoding]::UTF8.GetBytes("# PRIVATE_COMMENT_SENTINEL`r`nlocal all all scram-sha-256`r`nhost all all 127.0.0.1/32 scram-sha-256`r`n")
[IO.File]::WriteAllBytes($hba,$bytes);[IO.File]::WriteAllBytes($psqlPath,@())
# Main scenarios use a modern descriptor; the explicit legacy fixture below covers the spare layout.
$initialAcl=Get-Acl -LiteralPath $hba
$modernAcl=[Security.AccessControl.FileSecurity]::new();$modernAcl.SetSecurityDescriptorSddlForm($initialAcl.GetSecurityDescriptorSddlForm('Owner,Group,Access'),[Security.AccessControl.AccessControlSections]'Owner,Group,Access')
Set-PaperHbaAclObject $hba $modernAcl
$script:base=[pscustomobject]@{version='PAPER_HBA_METADATA_V1';database='marketbrain';databaseOid='16389';clusterId='7679149914381758260';serverPort=5432;serverVersion=180006;serverStartEpoch='1790000000.123456';adminSuperuser=$true;writerCount=1;writerLoginEnabled=$false;hbaPath=$hba;hbaBytes=$bytes.Length;hbaHash=(Get-PaperRestrictionHash $bytes);hbaRuleCount=2;hbaErrorCount=0;readOnly=$true}
$plan=Read-PaperHbaLocalPlan $script:base;$sddl=Get-PaperHbaSddl $hba
$dir=New-PaperHbaBackup $hba $plan $backupRoot ([Guid]::NewGuid().ToString('N'))
$journal=Read-PaperHbaBackup $dir
Check ($journal.originalHash -ceq $plan.originalHash) 'Verified backup'
Assert-PaperPrivateAcl $dir
Check ((Restore-PaperHbaBackup $dir) -ceq 'ORIGINAL_ALREADY_PRESENT') 'Pre-apply recovery no-op'
$state=@{};Invoke-PaperHbaTransaction $dir {Check ((Get-PaperRestrictionHash (Read-PaperHbaBytes $hba)) -ceq $plan.candidateHash) 'Candidate installed'} $state
Check ($state.postValidationPassed -and $state.hbaChanged) 'Apply success flags'
Check ((Get-PaperHbaSddl $hba) -ceq $sddl) 'Real ACL preserved'
Check ((Restore-PaperHbaBackup $dir) -ceq 'ORIGINAL_RESTORED') 'Manual recovery from persisted backup'
Check ((Get-PaperHbaSddl $hba) -ceq $sddl -and (Get-PaperRestrictionHash (Read-PaperHbaBytes $hba)) -ceq $plan.originalHash) 'Original bytes and ACL restored'
# Verify diagnostic precision without exposing original bytes, raw descriptors or account SIDs.
$diagnostic=$null
try{Assert-PaperHbaFileState $hba ('0'*64) $sddl 'TEST_CONTENT'}catch{$diagnostic=$_.Exception.Data['fileState']}
Check ($diagnostic -and -not $diagnostic.contentMatches -and $diagnostic.sddlMatches -and $diagnostic.phase -ceq 'TEST_CONTENT') 'Content mismatch evidence'
Check (($diagnostic|ConvertTo-Json -Depth 8) -notmatch 'PRIVATE_COMMENT_SENTINEL|S-1-5-|originalSddl') 'Safe content mismatch evidence'
$state=@{};Denied {Invoke-PaperHbaTransaction $dir {throw 'TEST_POST_FAILURE'} $state} 'TEST_POST_FAILURE'
Check ($state.rollbackFileVerified -and $state.recoveryStatus -ceq 'ORIGINAL_RESTORED') 'Automatic rollback after post-check failure'
[IO.File]::WriteAllText($hba,'external administrator change')
Denied {Restore-PaperHbaBackup $dir} 'HBA_STAGE_RECOVERY_OWNERSHIP_LOST'
Check ([IO.File]::ReadAllText($hba) -ceq 'external administrator change') 'External edit not overwritten'
[IO.File]::WriteAllBytes($hba,$bytes)
$bad=Join-Path $work 'bad.json';[IO.File]::WriteAllText($bad,'{}');Denied {Read-PaperHbaAcceptedPlan $bad} 'HBA_STAGE_EVIDENCE_HASH_MISMATCH'
[IO.File]::WriteAllText((Join-Path $dir 'original.bin'),'tampered')
Denied {Read-PaperHbaBackup $dir} 'HBA_STAGE_BACKUP_HASH_MISMATCH'
[IO.File]::WriteAllBytes((Join-Path $dir 'original.bin'),$bytes)
Denied {New-PaperHbaBackup $hba $plan $backupRoot $journal.runId} 'HBA_STAGE_BACKUP_ALREADY_EXISTS'
# Refuse external ACL/content changes even during failure recovery.
$state=@{};Denied {Invoke-PaperHbaTransaction $dir {[IO.File]::WriteAllText($hba,'concurrent external edit');throw 'TEST_EXTERNAL_EDIT'} $state} 'TEST_EXTERNAL_EDIT'
Check ($state.recoveryStatus -ceq 'MANUAL_RECOVERY_REQUIRED' -and -not $state['rollbackFileVerified']) 'Recovery refuses unknown content'
Check ([IO.File]::ReadAllText($hba) -ceq 'concurrent external edit') 'Unknown content preserved after failed verification'
[IO.File]::WriteAllBytes($hba,$bytes)
Protect-PaperHbaBackupAcl $hba
Denied {Set-PaperHbaFileFromBackup $dir} 'HBA_STAGE_FILE_OR_ACL_DRIFT'
$diagnostic=$null
try{Assert-PaperHbaFileState $hba $plan.originalHash $sddl 'TEST_ACL'}catch{$diagnostic=$_.Exception.Data['fileState']}
Check ($diagnostic -and $diagnostic.contentMatches -and -not $diagnostic.sddlMatches -and -not $diagnostic.daclMatches) 'ACL mismatch evidence'
Check (($diagnostic|ConvertTo-Json -Depth 8) -notmatch 'PRIVATE_COMMENT_SENTINEL|S-1-5-|originalSddl') 'Safe ACL mismatch evidence'
Set-FixtureDacl $hba $sddl
$lock=[IO.File]::Open($hba,'Open','Read','None')
try{$state=@{};$failed=$false;try{Invoke-PaperHbaTransaction $dir {} $state}catch{$failed=$true};Check ($failed -and -not $state['postValidationPassed']) 'File lock prevents replacement'}finally{$lock.Dispose()}
Assert-PaperHbaFileState $hba $plan.originalHash $sddl
foreach($variant in @('LF','UTF8_BOM')){
    $content=[Text.Encoding]::UTF8.GetBytes("# fixture`nlocal all all scram-sha-256`n")
    if($variant -ceq 'UTF8_BOM'){$content=[byte[]](@(239,187,191)+@($content))}
    [IO.File]::WriteAllBytes($hba,$content)
    $m=$script:base|ConvertTo-Json|ConvertFrom-Json;$m.hbaHash=Get-PaperRestrictionHash $content;$m.hbaBytes=$content.Length;$m.hbaRuleCount=1
    $p=Read-PaperHbaLocalPlan $m;$b=New-PaperHbaBackup $hba $p $backupRoot ([Guid]::NewGuid().ToString('N'))
    Set-PaperHbaFileFromBackup $b;$null=Restore-PaperHbaBackup $b
    Check ((Get-PaperRestrictionHash (Read-PaperHbaBytes $hba)) -ceq $m.hbaHash) ('Encoding recovery '+$variant)
}
[IO.File]::WriteAllBytes($hba,$bytes)

# Cover permission inheritance rather than relying only on this machine's TEMP ACL.
foreach($aclCase in @('PROTECTED','CREATOR_OWNER','INHERITED_DENY','LEGACY_AUTO_INHERITED')){
    $rehearsal.phase='ACL_FIXTURE_'+$aclCase
    $aclDir=Join-Path $work $aclCase;[void][IO.Directory]::CreateDirectory($aclDir)
    $parentAcl=[Security.AccessControl.DirectorySecurity]::new();$parentAcl.SetAccessRuleProtection($true,$false)
    $userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $parentAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($userSid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    if($aclCase -ceq 'LEGACY_AUTO_INHERITED'){
        foreach($sid in @('S-1-5-18','S-1-5-32-544')){$parentAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))}
    }
    if($aclCase -ceq 'CREATOR_OWNER'){$parentAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-3-0'),'FullControl','ContainerInherit,ObjectInherit','InheritOnly','Allow'))}
    if($aclCase -ceq 'INHERITED_DENY'){$parentAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-7'),'WriteData','ObjectInherit','InheritOnly','Deny'))}
    Set-PaperHbaAclObject $aclDir $parentAcl -Directory
    $aclTarget=Join-Path $aclDir 'pg_hba.conf';[IO.File]::WriteAllBytes($aclTarget,$bytes)
    if($aclCase -ceq 'PROTECTED'){Protect-PaperHbaBackupAcl $aclTarget}
    if($aclCase -ceq 'LEGACY_AUTO_INHERITED'){
        $legacy=[Security.AccessControl.RawSecurityDescriptor]::new((Get-PaperHbaSddl $aclTarget))
        $legacy.SetFlags([Security.AccessControl.ControlFlags]([int]$legacy.ControlFlags -band (-bnot 1024)))
        Set-FixtureDacl $aclTarget ($legacy.GetSddlForm('Owner,Group,Access'))
        Check (([int]([Security.AccessControl.RawSecurityDescriptor]::new((Get-PaperHbaSddl $aclTarget))).ControlFlags -band 1024) -eq 0) 'Legacy fixture has no auto-inherited descriptor bit'
    }
    $aclBefore=Get-PaperHbaSddl $aclTarget
    $m=$script:base|ConvertTo-Json|ConvertFrom-Json;$m.hbaPath=$aclTarget
    $p=Read-PaperHbaLocalPlan $m;$b=New-PaperHbaBackup $aclTarget $p $backupRoot ([Guid]::NewGuid().ToString('N'))
    $observations=[Collections.ArrayList]::new()
    Set-PaperHbaFileFromBackup $b -AclObservations $observations
    Check (((Get-PaperHbaSddl $aclTarget) -ceq $aclBefore) -or (Test-PaperHbaAutoInheritedOnly $aclBefore (Get-PaperHbaSddl $aclTarget))) ('Apply preserves permissions '+$aclCase)
    $null=Restore-PaperHbaBackup $b -AclObservations $observations
    Check ((((Get-PaperHbaSddl $aclTarget) -ceq $aclBefore) -or (Test-PaperHbaAutoInheritedOnly $aclBefore (Get-PaperHbaSddl $aclTarget))) -and (Get-PaperRestrictionHash (Read-PaperHbaBytes $aclTarget)) -ceq $p.originalHash) ('Recovery preserves '+$aclCase)
    if($aclCase -ceq 'LEGACY_AUTO_INHERITED'){
        Check ($observations.Count -ge 4) 'Legacy apply and recovery recorded metadata-only differences'
        $rehearsal['legacyAclRegression']=[ordered]@{passed=$true;metadataDifferences=$observations.ToArray();targetPermissionsPreserved=$true;originalBytesRestored=$true}
        # Recreate the reviewed pre-apply descriptor, then inject a post-validation failure.
        Set-FixtureDacl $aclTarget $aclBefore
        $failedState=@{};Denied {Invoke-PaperHbaTransaction $b {throw 'TEST_LEGACY_POST_FAILURE'} $failedState} 'TEST_LEGACY_POST_FAILURE'
        Check ($failedState.rollbackFileVerified -and $failedState.recoveryStatus -ceq 'ORIGINAL_RESTORED' -and (Test-PaperHbaAutoInheritedOnly $aclBefore (Get-PaperHbaSddl $aclTarget))) 'Legacy permission-preserving automatic rollback'
    }
}

# Exercise complete runner, including actual fixture replacement and rollback.
$rehearsal.phase='MOCKED_STAGING_RUNNERS'
Write-Progress -Activity 'Generated-file HBA rehearsal' -Status 'Mocked staging workflows' -PercentComplete 25
Write-Host '[25%] File checks passed; testing mocked staging workflows.'
$script:backupImplementation=(Get-Item Function:\New-PaperHbaBackup).ScriptBlock
function New-PaperHbaBackup($Target,$Plan,$BackupRoot,$RunId){& $script:backupImplementation $Target $Plan (Join-Path $work 'runner-backups') $RunId}
function Read-PaperHbaAcceptedPlan($Path){if($script:mode -ceq 'bad-input'){throw 'HBA_STAGE_EVIDENCE_HASH_MISMATCH'};[pscustomobject]@{metadata=$script:base;filePlan=$plan}}
function git {$global:LASTEXITCODE=0;if($args -contains 'status' -and $script:mode -ceq 'dirty'){' M unrelated'};if($args -contains 'rev-parse'){'a'*40}}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=$Name}}
function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){ConvertTo-SecureString 'PASSWORD_SENTINEL' -AsPlainText -Force}elseif($Prompt -like '*type marketbrain*'){'marketbrain'}elseif($Prompt -like '*APPLY WRITER*'){if($script:mode -ceq 'declined'){'NO'}else{'APPLY WRITER RESTRICTION'}}else{'postgres'}}
function Invoke-PaperInstallerPsql($Executable,$Database,$Port,$Admin,$Password,$Sql){
    $script:dbCalls++;Check ($Sql -ceq (New-PaperHbaMetadataSql)) 'Read-only bounded SQL only'
    $v=$script:base|ConvertTo-Json|ConvertFrom-Json
    $current=Read-PaperHbaBytes $hba;$changed=(Get-PaperRestrictionHash $current) -cne $plan.originalHash
    if($changed){$v.hbaHash=$plan.candidateHash;$v.hbaBytes=$plan.candidateBytes;$v.hbaRuleCount=6}
    if($script:mode -ceq 'wrong-db'){$v.databaseOid='99'}
    if($script:mode -ceq 'enabled-writer'){$v.writerLoginEnabled=$true}
    if($script:mode -ceq 'pre-drift' -and $script:dbCalls -eq 2){$v.serverStartEpoch='1790000001.123456'}
    if($changed -and $script:mode -ceq 'parse-error'){$v.hbaErrorCount=1}
    if($changed -and $script:mode -ceq 'bad-count'){$v.hbaRuleCount=5}
    if($changed -and $script:mode -ceq 'post-drift'){$v.serverStartEpoch='1790000001.123456'}
    [pscustomobject]@{exitCode=if($changed -and $script:mode -ceq 'sql-error'){1}else{0};timedOut=($changed -and $script:mode -ceq 'sql-timeout');elapsedSeconds=0.01;sqlStates=@();stdout=($v|ConvertTo-Json -Compress)}
}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
    Check ($LimitSeconds -le 60 -and ($Arguments -join ' ') -notmatch 'PASSWORD_SENTINEL') 'Bounded native call without credentials'
    $output='';$exit=0
    if($Executable -ceq 'javac'){$folder=$Arguments[3];$package=Join-Path $folder 'in\marketbrain\paper';[void][IO.Directory]::CreateDirectory($package);[IO.File]::WriteAllBytes((Join-Path $package 'PaperApplicationRouteProbe.class'),@());if($script:mode -ceq 'compile-fail'){$exit=1}}
    elseif($Arguments[0] -ceq 'ps'){$output=switch($script:mode){'no-container'{''};'two-containers'{"abcdef012345`nabcdef678901"};'bad-container'{'not-an-id'};default{'abcdef012345'}}}
    elseif($Arguments -contains 'java'){
        $v=[pscustomobject]@{version='PAPER_APPLICATION_ROUTE_V1';status='READ_ONLY_APPLICATION_ROUTE_OBSERVED';database='marketbrain';databaseOid='16389';applicationUser='marketbrain_app';sessionUser='marketbrain_app';clientAddress='127.0.0.1';serverAddress='127.0.0.1';serverPort=5432;serverStartEpoch='1790000000.123456';applicationName=('mb-route-'+$Arguments[-1]);readOnly=$true;databaseWritesPerformed=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false}
        if($script:mode -ceq 'post-route' -and (Get-PaperRestrictionHash (Read-PaperHbaBytes $hba)) -ceq $plan.candidateHash){$v.clientAddress='192.168.1.20'}
        $output=$v|ConvertTo-Json -Compress
    }
    if($script:mode -ceq 'cleanup-error' -and $Arguments -contains 'rmdir'){$exit=1}
    if($script:mode -ceq 'copy-fail' -and $Arguments[0] -ceq 'cp'){$exit=1}
    [pscustomobject]@{stdout=$output;stderr='PASSWORD_SENTINEL';exitCode=$exit;timedOut=$false;elapsedSeconds=0.01}
}
$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SetPaperWriterHbaRestriction.ps1') -Raw
$text=$text.Replace('#Requires -Version 7.0','')
$text=[regex]::Replace($text,'(?m)^foreach\(\$file in @\(''NumericalHistoryEvidence.*\r?\n','')
$text=$text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$text=[regex]::Replace($text,'(?m)^    \$principal=.*\r?\n','')
$text=[regex]::Replace($text,'(?m)^    if\(-not \$principal\.IsInRole.*\r?\n','')
# Local test uses a process-specific mutex, never the runtime global mutex.
$text=$text.Replace('Global\MarketBrainPaperHbaRestrictionV1',('Local\MarketBrainHbaTest'+$PID))
$runner=[scriptblock]::Create($text)
$modes=@('pass','preview','bad-input','dirty','declined','wrong-db','enabled-writer','pre-drift','parse-error','bad-count','post-drift','post-route','sql-error','sql-timeout','no-container','two-containers','bad-container','compile-fail','copy-fail','cleanup-error')
foreach($script:mode in $modes){
    $rehearsal.phase='STAGING_'+$script:mode
    $percent=25+[int](55*[array]::IndexOf($modes,$script:mode)/$modes.Count)
    Write-Progress -Activity 'Generated-file HBA rehearsal' -Status $rehearsal.phase -PercentComplete $percent
    Write-Host ('['+$percent+'%] Mocked staging case: '+$script:mode)
    $output=Join-Path $work $script:mode;$script:dbCalls=0;$threw=$false
    try {& $runner -ReviewedPlanPath $bad -Apply:($script:mode -cne 'preview') -PostgreSqlBin $work -OutputDirectory $output 6>$null}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) 'One shareable report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$v=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'PASSWORD_SENTINEL|PRIVATE_COMMENT_SENTINEL|originalSddl') 'No credentials or private backup content in report'
    foreach($flag in @('databaseWritesPerformed','firewallChanged','writerLoginAttempted','credentialsSaved','applicationWriterActivated','actionExecutionEnabled')){Check ($v.$flag -is [bool] -and -not $v.$flag) ('Safety '+$flag)}
    if($script:mode -ceq 'pass'){Check (-not $threw -and $v.status -ceq 'HBA_RESTRICTION_STAGED_WRITER_DISABLED' -and $v.cleanupComplete -and $v.postValidationPassed) 'Successful full workflow'}
    elseif($script:mode -ceq 'preview'){Check (-not $threw -and $v.status -ceq 'HBA_STAGE_PREFLIGHT_PASSED_APPLY_NOT_REQUESTED' -and -not $v.backupDirectory -and -not $v.replacementAttempted) 'No apply without switch'}
    elseif($script:mode -ceq 'cleanup-error'){Check ($threw -and $v.status -ceq 'STAGED_CLEANUP_REVIEW_REQUIRED' -and $v.postValidationPassed) 'Cleanup failure does not misreport completed staging'}
    else{Check ($threw -and $v.status -like 'FAILED*' -and $v.failureCode) ('Failed safely '+$script:mode)}
    if($script:mode -in @('parse-error','bad-count','post-drift','post-route','sql-error','sql-timeout')){Check ($v.status -ceq 'FAILED_ROLLED_BACK' -and $v.rollbackFileVerified -and $v.rollbackConnectionsVerified) ('Rollback '+$script:mode)}
    if($script:mode -in @('no-container','two-containers','bad-container','bad-input','dirty')){Check ($script:dbCalls -eq 0 -and -not $v.replacementAttempted) 'No DB on preflight failures'}
    if($script:mode -ceq 'no-container'){Check ($v.failureCode -ceq 'HBA_STAGE_APPLICATION_NOT_RUNNING') 'Precise stopped-container diagnosis'}
    if($v.backupDirectory){$null=Restore-PaperHbaBackup $v.backupDirectory}
    Check ((Get-PaperRestrictionHash (Read-PaperHbaBytes $hba)) -ceq $plan.originalHash -and (Get-PaperHbaSddl $hba) -ceq $sddl) 'Original fixture intact at scenario end'
}
# Standalone crash-recovery wrapper: only fixture paths, no application or DB needed.
$rehearsal.phase='MOCKED_RECOVERY_RUNNERS'
Write-Progress -Activity 'Generated-file HBA rehearsal' -Status 'Mocked recovery workflows' -PercentComplete 85
Write-Host '[85%] Testing independent recovery on generated files.'
$recoveryText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RestorePaperWriterHbaRestriction.ps1') -Raw
Check ($recoveryText.Contains('C:\\MarketBrainData\\Secrets\\PaperWriterHba\\[a-f0-9]{32}')) 'Production recovery root pinned'
$recoveryText=$recoveryText.Replace('#Requires -Version 7.0','')
$recoveryText=[regex]::Replace($recoveryText,'(?m)^foreach\(\$file in @\(''NumericalHistoryEvidence.*\r?\n','')
$recoveryText=$recoveryText.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$recoveryText=[regex]::Replace($recoveryText,'(?m)^    \$principal=.*\r?\n','')
$recoveryText=[regex]::Replace($recoveryText,'(?m)^    if\(-not \$principal\.IsInRole.*\r?\n','')
$recoveryText=[regex]::Replace($recoveryText,'(?m)^    if\(\$dir -cnotmatch.*\r?\n','')
$recoveryText=$recoveryText.Replace('Global\MarketBrainPaperHbaRestrictionV1',('Local\MarketBrainHbaTest'+$PID))
$recoveryRunner=[scriptblock]::Create($recoveryText)
function Read-Host {param($Prompt);if($script:mode -ceq 'recovery-declined'){'NO'}else{'RESTORE ORIGINAL HBA'}}
foreach($script:mode in @('recovery-pass','recovery-already','recovery-external','recovery-declined')){
    $rehearsal.phase='RECOVERY_'+$script:mode
    Write-Host ('[85%] Mocked recovery case: '+$script:mode)
    if($script:mode -ceq 'recovery-pass'){Set-PaperHbaFileFromBackup $dir}
    if($script:mode -ceq 'recovery-external'){[IO.File]::WriteAllText($hba,'unknown change')}
    $output=Join-Path $work $script:mode;$threw=$false
    try{& $recoveryRunner -ReviewedPlanPath $bad -RecoveryDirectory $dir -OutputDirectory $output 6>$null}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) 'One recovery report'
    $v=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    if($script:mode -in @('recovery-pass','recovery-already')){Check (-not $threw -and $v.status -ceq 'ORIGINAL_FILE_VERIFIED_CONNECTION_RECHECK_REQUIRED') 'Standalone recovery success'}
    else{Check ($threw -and $v.status -ceq 'RECOVERY_REVIEW_REQUIRED') 'Recovery refusal'}
    Check (-not $v.databaseContacted -and -not $v.connectionsReverified -and -not $v.actionExecutionEnabled) 'Recovery does not claim connection verification'
    if($script:mode -ceq 'recovery-external'){Check ([IO.File]::ReadAllText($hba) -ceq 'unknown change') 'Standalone recovery preserves external edits';[IO.File]::WriteAllBytes($hba,$bytes)}
}
foreach($file in @('PaperWriterHbaStage.ps1','SetPaperWriterHbaRestriction.ps1','RestorePaperWriterHbaRestriction.ps1','TestPaperWriterHbaStage.ps1')){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) ('Parses '+$file)}
# Explicitly validated generated workspace only; no runtime paths enter this test cleanup.
$resolved=[IO.Path]::GetFullPath($work);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-hba-stage-test-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup'}
Remove-Item -LiteralPath $resolved -Recurse -Force
$rehearsal.fixtureCleanupComplete=$true
$rehearsal.status='REHEARSAL_PASSED_NO_REAL_CHANGES'
$rehearsal.phase='COMPLETE'
Write-Host "PASS: $script:checks HBA staging assertions; $($modes.Count) staging and 4 recovery runner scenarios; only generated files and mocked services."
}catch {
    $rehearsal.status='REHEARSAL_FAILED_APPLY_BLOCKED'
    $rehearsal.failureCode='SYNTHETIC_REHEARSAL_FAILED'
    if($_.Exception.Message -cmatch '^(HBA_STAGE|HBA_PLAN|RESTRICTION|CUSTODY)_[A-Z_]+$'){$rehearsal.failureCode=$_.Exception.Message}
    $rehearsal.failureLine=$_.InvocationInfo.ScriptLineNumber
    if($_.Exception.Data.Contains('fileState')){$rehearsal.fileState=$_.Exception.Data['fileState']}
    throw
}finally {
    $timer.Stop();$rehearsal.elapsedSeconds=$timer.Elapsed.TotalSeconds;$rehearsal.assertionsPassed=$script:checks
    [IO.File]::WriteAllText($reportPath,($rehearsal|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Write-Progress -Activity 'Generated-file HBA rehearsal' -Completed
    Write-Host ('[100%] '+$rehearsal.status+'; share this ONE file: '+$reportPath)
}
