# Pure descriptor tests. No filesystem, database, native ACL writes or credentials.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterHbaStage.ps1')
$checks=0
function Verify([bool]$Value,[string]$Name){if(-not $Value){throw ('ACL comparison regression: '+$Name)};$script:checks++}
$baseline='O:SYG:SYD:(D;;FW;;;AN)(A;;FR;;;SY)(A;;FR;;;BA)'
$auto=$baseline.Replace('D:','D:AI')
Verify (Test-PaperHbaAutoInheritedOnly $baseline $auto) 'Only auto-inherited descriptor bit accepted'
Verify (Test-PaperHbaAutoInheritedOnly $auto $baseline) 'Only that bit can differ in reverse'
Verify (-not (Test-PaperHbaAutoInheritedOnly $baseline $baseline)) 'Equal descriptors are not reported as normalization'
$mutations=[ordered]@{
    Owner=$auto.Replace('O:SY','O:BA')
    Group=$auto.Replace('G:SY','G:BA')
    Rights=$auto.Replace('(A;;FR;;;SY)','(A;;FA;;;SY)')
    Trustee=$auto.Replace('(A;;FR;;;BA)','(A;;FR;;;BU)')
    AllowDeny=$auto.Replace('(D;;FW;;;AN)','(A;;FW;;;AN)')
    AceOrder=$auto.Replace('(A;;FR;;;SY)(A;;FR;;;BA)','(A;;FR;;;BA)(A;;FR;;;SY)')
    AceInherited=$auto.Replace('(A;;FR;;;SY)','(A;ID;FR;;;SY)')
    AceInheritance=$auto.Replace('(A;;FR;;;SY)','(A;OI;FR;;;SY)')
    Protection=$auto.Replace('D:AI','D:PAI')
    InheritanceRequest=$auto.Replace('D:AI','D:ARAI')
    AddedAce=($auto+'(A;;FA;;;WD)')
    RemovedAce=$auto.Replace('(D;;FW;;;AN)','')
    EmptyDacl='O:SYG:SYD:AI'
    NullDacl='O:SYG:SYD:AINO_ACCESS_CONTROL'
}
foreach($case in $mutations.GetEnumerator()){Verify (-not (Test-PaperHbaAutoInheritedOnly $baseline $case.Value)) $case.Key}
# Exercise the public guard: only explicit owned-write/recovery phases permit metadata differences.
function Get-PaperHbaSddl {return $script:returnedSddl}
function Read-PaperHbaBytes {return ,([byte[]]@(1))}
function Get-PaperRestrictionHash {return 'SYNTHETIC_HASH'}
$script:returnedSddl=$auto
$notes=[Collections.ArrayList]::new()
Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline 'PREPARED_TEMPORARY_FILE' -AllowAutoInheritedMetadata -AclObservations $notes
Verify ($notes.Count -eq 1 -and $notes[0].allOtherDescriptorBytesMatch) 'Accepted difference logged'
foreach($phase in @('FILE_STATE','BEFORE_REPLACEMENT','IMMEDIATELY_BEFORE_REPLACEMENT','UNRECOGNIZED')){
    $caught=$null
    try{Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline $phase -AllowAutoInheritedMetadata}catch{$caught=$_.Exception.Message}
    Verify ($caught -ceq 'HBA_STAGE_FILE_OR_ACL_DRIFT') ('Exact target check '+$phase)
}
$caught=$null
try{Assert-PaperHbaFileState 'synthetic' 'WRONG_HASH' $baseline 'PREPARED_TEMPORARY_FILE' -AllowAutoInheritedMetadata}catch{$caught=$_.Exception.Message}
Verify ($caught -ceq 'HBA_STAGE_FILE_OR_ACL_DRIFT') 'Content change rejected despite allowed descriptor metadata'
foreach($case in $mutations.GetEnumerator()){
    $script:returnedSddl=$case.Value;$caught=$null
    try{Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline 'PREPARED_TEMPORARY_FILE' -AllowAutoInheritedMetadata}catch{$caught=$_.Exception.Message}
    Verify ($caught -ceq 'HBA_STAGE_FILE_OR_ACL_DRIFT') ('Temporary permission change rejected '+$case.Key)
}
Verify ($notes.Count -eq 1) 'No additional accepted-difference record on failures'
foreach($phase in @('PREPARED_TEMPORARY_FILE','AFTER_REPLACEMENT','POST_VALIDATION','RECOVERY_CANDIDATE','RECOVERY_BEFORE_REPLACEMENT','RECOVERY_ORIGINAL')){
    $script:returnedSddl=$auto
    $phaseNotes=[Collections.ArrayList]::new()
    Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline $phase -AllowAutoInheritedMetadata -AclObservations $phaseNotes
    Verify ($phaseNotes.Count -eq 1) ('Owned phase permits metadata only '+$phase)
    $caught=$null
    try{Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline $phase}catch{$caught=$_.Exception.Message}
    Verify ($caught -ceq 'HBA_STAGE_FILE_OR_ACL_DRIFT') ('Explicit opt-in required '+$phase)
    foreach($case in $mutations.GetEnumerator()){
        $script:returnedSddl=$case.Value;$caught=$null
        try{Assert-PaperHbaFileState 'synthetic' 'SYNTHETIC_HASH' $baseline $phase -AllowAutoInheritedMetadata}catch{$caught=$_.Exception.Message}
        Verify ($caught -ceq 'HBA_STAGE_FILE_OR_ACL_DRIFT') ('Owned phase rejects permission change '+$phase+' '+$case.Key)
    }
}
[pscustomobject]@{status='PASSED';checks=$checks;permissionsCompared='Full binary descriptor except explicit owned-write DACL_AUTO_INHERITED bit';preApplyTargetChecksRemainExact=$true}
