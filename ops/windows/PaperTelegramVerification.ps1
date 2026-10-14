# Definitions only. Fixed isolated fixture contract; no network, database or credential access on import.
function Get-PaperTelegramCheckNames([string]$Phase) {
    if($Phase -ceq '--prepare') { return @(
        'install_fixture_and_authenticate_real_connector','accept_callback_records_without_execution','reject_callback_skips_quote',
        'duplicate_callback_reuses_receipt','opposing_action_cannot_replace_receipt','group_and_malformed_callbacks_stop_before_credential_read',
        'wrong_user_and_unknown_token_cannot_record','expired_callback_cannot_accept','unavailable_quote_blocks_accept',
        'credential_rotation_is_read_on_next_connection','nologin_revocation_prevents_callback_and_preserves_pending',
        'unsafe_role_attributes_block_connector','money_secret_and_ddl_operations_are_denied',
        'concurrent_callbacks_have_one_terminal_receipt','cash_revision_and_orders_unchanged') }
    if($Phase -ceq '--recover') { return @('fresh_process_replays_saved_receipt_without_quote',
        'fresh_process_reject_works_with_restricted_login','restart_cash_revision_and_orders_unchanged') }
    throw 'Unknown Telegram verification phase.'
}
function Assert-PaperTelegramPhase($Result,[string]$Phase,[string]$Schema) {
    if($Result.version -cne 'PAPER_TELEGRAM_REVIEW_V1' -or $Result.status -cne 'ISOLATED_TELEGRAM_REVIEW_PASSED' -or
        $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong Telegram fixture identity.'}
    foreach($flag in @('applicationDatabaseAccessed','applicationWriterActivated','actionExecutionEnabled')) {
        if($Result.$flag -isnot [bool] -or $Result.$flag){throw 'Unsafe Telegram fixture flag.'}
    }
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Missing synthetic write disclosure.'}
    foreach($field in @('failedCount','telegramCalls','providerCalls','modelCalls','reservedCashPaise','ledgerRevision','orderCount','fillCount')) {
        Assert-PaperExact $Result.$field 0 $field
    }
    Assert-PaperExact $Result.cashPaise 10000000 'cashPaise'
    $names=@(Get-PaperTelegramCheckNames $Phase)
    Assert-PaperExact $Result.checkCount $names.Count 'checkCount'
    if(@($Result.checks).Count -ne $names.Count){throw 'Incomplete Telegram checks.'}
    foreach($name in $names) {
        $rows=@($Result.checks|Where-Object name -CEQ $name)
        if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw 'Missing or failed Telegram check.'}
        Assert-PaperApprovalTiming $rows[0].elapsedMillis
    }
    Assert-PaperApprovalTiming $Result.elapsedSeconds
}
