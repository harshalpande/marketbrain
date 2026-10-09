# Definitions only; no Docker, application or key provisioning on import.
function Assert-PaperStoragePhase($Result,[string]$Phase,[string]$Schema){
    if($Result.version -cne 'PAPER_STORAGE_REVIEW_V1' -or $Result.status -cne 'ISOLATED_STORAGE_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong storage phase.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw 'Unsafe storage flag.'}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Missing synthetic write disclosure.'}
    foreach($name in @('failedCount','providerCalls','telegramCalls','modelCalls','reservedCashPaise','ledgerRevision','orderCount','fillCount','proposalCount','deliveryCount')){Assert-PaperExact $Result.$name 0 $name}
    Assert-PaperExact $Result.cashPaise 10000000 'cash';Assert-PaperExact $Result.bindingCount 1 'binding'
    $names=if($Phase -ceq '--prepare'){@('migration_preserves_account_and_empty_approvals','first_key_binding_verifies_encrypted_probe','same_key_replay_preserves_binding','wrong_key_does_not_replace_binding','missing_binding_is_not_created_by_read','concurrent_setup_keeps_single_binding','unbound_existing_proposals_block_setup','key_binding_cannot_be_updated_or_deleted','failed_binding_insert_rolls_back','prepare_storage_restart_fixture')}elseif($Phase -ceq '--recover'){@('restart_accepts_original_key_without_rebinding','restart_retains_account_and_no_approval_activity')}else{throw 'Unknown phase'}
    Assert-PaperExact $Result.checkCount $names.Count 'checkCount'
    if(@($Result.checks).Count -ne $names.Count){throw 'Missing checks'}
    foreach($name in $names){$rows=@($Result.checks|Where-Object name -CEQ $name);if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw 'Missing or failed storage check'};Assert-PaperApprovalTiming $rows[0].elapsedMillis}
    Assert-PaperApprovalTiming $Result.elapsedSeconds
}
