function Assert-PaytmAcceptedMaintenance([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 200000){throw 'BACKUP_EVIDENCE_INVALID'}
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if($hash -cne '51F1CC9FE4F54AC8CAF36F298F8CB26E4D0947B72F05FE7E52A500A470CB6F27'){throw 'BACKUP_REVIEWED_EVIDENCE_HASH_MISMATCH'}
    [pscustomobject]@{runId='f44e98badcf348a6aa7f0967236b4a9b';sha256=$hash}
}
function New-PaytmBackupPayload([string]$RunId,[string]$Helpers,[string]$Source) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or ($Helpers.Length+$Source.Length) -gt 26000 -or ($Helpers+$Source).Contains('MB_PRIVATE_BACKUP') -or ($Helpers+$Source).Contains([char]0)){throw 'BACKUP_PAYLOAD_INVALID'}
    "sudo -n timeout --kill-after=10s 600s bash <<'MB_PRIVATE_BACKUP'`n"+$Helpers.Replace("`r",'')+"`n"+$Source.Replace("`r",'')+"`npb_main '$RunId'`nMB_PRIVATE_BACKUP`n"
}
function Read-PaytmBackupReceipt([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 3000){throw 'BACKUP_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"))
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_BACKUP_$RunId" -or $lines[-1] -cne "END_PAYTM_BACKUP_$RunId"){throw 'BACKUP_CURRENT_BLOCK_REQUIRED'}
    $expected=@('VERSION','RUN_ID','PHASE','EXIT_CODE','DIRECTORY_CREATED','ARCHIVE_VERIFIED','ARCHIVE_SHA256','ARCHIVE_BYTES','PACKAGE_STATE_UNCHANGED','CAPTURE_COMPLETE');$fields=[ordered]@{}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9_]{1,64})$'){throw 'BACKUP_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $expected -or $fields.Contains($key)){throw 'BACKUP_FIELD_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $expected.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'BACKUP_INCOMPLETE'}
    if($fields.PHASE -cnotin @('PRECHECK','CREATE_DIRECTORY','CAPTURE','VERIFY','COMPLETE') -or $fields.EXIT_CODE -cnotmatch '^\d{1,3}$' -or $fields.ARCHIVE_BYTES -cnotmatch '^\d{1,12}$'){throw 'BACKUP_STATE_INVALID'}
    foreach($key in @('DIRECTORY_CREATED','ARCHIVE_VERIFIED','PACKAGE_STATE_UNCHANGED')){if($fields[$key] -cnotin @('yes','no')){throw 'BACKUP_STATE_INVALID'}}
    if($fields.ARCHIVE_SHA256 -cne 'NONE' -and $fields.ARCHIVE_SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'BACKUP_HASH_INVALID'}
    $passed=$fields.PHASE -ceq 'COMPLETE' -and $fields.EXIT_CODE -ceq '0' -and $fields.DIRECTORY_CREATED -ceq 'yes' -and $fields.ARCHIVE_VERIFIED -ceq 'yes' -and $fields.PACKAGE_STATE_UNCHANGED -ceq 'yes' -and $fields.ARCHIVE_SHA256 -cne 'NONE' -and [long]$fields.ARCHIVE_BYTES -gt 0
    [pscustomobject]@{fields=$fields;archiveComparisonPassed=$passed;privateDirectory=if($fields.DIRECTORY_CREATED -ceq 'yes'){"/var/backups/marketbrain-maintenance/$RunId"}else{$null};offHostBackupVerified=$false;restoreTestPerformed=$false;fullSystemRollbackProven=$false;upgradeAuthorized=$false}
}
