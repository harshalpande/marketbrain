# Definitions only. Never runs Docker, connects to a database or reads a production key on import.
function Assert-PaperRecoveryPhase($Result,[string]$Phase,[string]$Schema){
    if($Result.version -cne 'PAPER_RECOVERY_REVIEW_V1' -or $Result.status -cne 'ISOLATED_RECOVERY_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong recovery phase identity.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled','approvalWriterReady')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw 'Unsafe recovery flag.'}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Missing synthetic write disclosure.'}
    foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls')){Assert-PaperExact $Result.$field 0 $field}
    $names=if($Phase -ceq '--prepare'){@('seed_backup_with_review_and_four_delivery_states','snapshot_covers_account_tokens_ciphertext_and_binding')}elseif($Phase -ceq '--recover'){@('restored_rows_match_source_snapshot','original_key_opens_restored_tokens_without_reissue','wrong_key_cannot_replace_restored_binding','restored_receipt_and_ciphertext_remain_immutable','restored_binding_quarantined_before_any_dispatch','quarantine_blocks_pending_and_attempted_resends','quarantine_blocks_callback_without_quote','audit_role_reads_only_redacted_views','audit_role_cannot_read_secrets_or_private_identity','audit_role_cannot_change_money_reviews_or_orders','audit_role_cannot_ddl_escalate_or_lock_as_writer','source_unchanged_and_restored_money_preserved')}else{throw 'Unknown phase.'}
    Assert-PaperExact $Result.checkCount $names.Count 'checkCount'
    if(@($Result.checks).Count -ne $names.Count){throw 'Incomplete checks.'}
    foreach($name in $names){$rows=@($Result.checks|Where-Object name -CEQ $name);if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw 'Missing or failed recovery check.'};Assert-PaperApprovalTiming $rows[0].elapsedMillis}
    Assert-PaperApprovalTiming $Result.elapsedSeconds
    if($Result.snapshotHash -isnot [string] -or $Result.snapshotHash -cnotmatch '^[a-f0-9]{64}$'){throw 'Missing snapshot digest.'}
    $tableCount=Get-PaperExactInteger $Result.snapshotTableCount 'tableCount';if($tableCount -lt 7 -or $tableCount -gt 256){throw 'Invalid table count.'}
}
function Assert-PaperRecoveryPair($Before,$After,$Backup){
    if($Before.snapshotHash -cne $After.snapshotHash -or $Before.snapshotTableCount -ne $After.snapshotTableCount){throw 'Restored snapshot mismatch.'}
    if($Backup.format -cne 'CUSTOM' -or $Backup.scope -cne 'SYNTHETIC_SCHEMA_ONLY' -or $Backup.sourceDatabase -cne 'paper_fixture' -or $Backup.restoredDatabase -cne 'paper_restore' -or $Backup.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid backup identity.'}
    if($Backup.restored -isnot [bool] -or -not $Backup.restored -or $Backup.containsApplicationData -isnot [bool] -or $Backup.containsApplicationData){throw 'Unsafe backup scope or incomplete restore.'}
}
