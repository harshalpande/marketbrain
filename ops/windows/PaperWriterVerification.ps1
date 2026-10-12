# Definitions only. No database, Docker, key, provider or model activity on import.
function Get-PaperWriterCheckNames([string]$Phase){
    if($Phase -ceq '--prepare'){
        return @('install_non_owner_writer_and_no_login_helper','accept_records_review_without_execution','reject_skips_quote_and_records_once','wrong_identity_and_unknown_token_stop_before_quote','private_chat_required','binding_revoked_during_quote_blocks_commit','quote_expiry_is_rechecked','quote_failure_and_out_of_zone_cannot_accept','account_change_during_quote_is_detected','concurrent_duplicate_has_one_receipt','writer_cannot_issue_proposals_or_tokens','writer_cannot_change_cash_reserves_positions_or_orders','writer_cannot_directly_edit_reviews_tokens_or_binding','writer_cannot_read_ciphertext_or_key_binding','writer_cannot_ddl_escalate_or_lock_base_tables','public_cannot_call_privileged_functions','command_checks_recipient_and_token_itself','command_rejects_execution_and_wrong_receipt_identity','reject_token_cannot_become_accept_receipt','callback_collision_rolls_back_terminal_write','lock_timeout_leaves_review_unwritten','fixed_search_path_and_helper_have_no_money_privilege','all_reviews_preserve_money_and_no_orders')
    }
    if($Phase -ceq '--recover'){return @('restart_replay_returns_saved_receipt_without_quote','restart_permissions_and_new_review_work','restart_preserves_money_and_no_orders')}
    throw 'Unknown writer verification phase.'
}
function Assert-PaperWriterPhase($Result,[string]$Phase,[string]$Schema){
    if($Result.version -cne 'PAPER_WRITER_REVIEW_V1' -or $Result.status -cne 'ISOLATED_WRITER_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong writer phase identity.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled','applicationWriterActivated')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw 'Unsafe writer flag.'}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Missing synthetic write disclosure.'}
    foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls','reservedCashPaise','ledgerRevision','orderCount','fillCount')){Assert-PaperExact $Result.$field 0 $field}
    Assert-PaperExact $Result.cashPaise 10000000 'cashPaise'
    $names=@(Get-PaperWriterCheckNames $Phase)
    Assert-PaperExact $Result.checkCount $names.Count 'checkCount'
    if(@($Result.checks).Count -ne $names.Count){throw 'Incomplete writer checks.'}
    foreach($name in $names){$rows=@($Result.checks|Where-Object name -CEQ $name);if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw 'Missing or failed writer check.'};Assert-PaperApprovalTiming $rows[0].elapsedMillis}
    Assert-PaperApprovalTiming $Result.elapsedSeconds
}
