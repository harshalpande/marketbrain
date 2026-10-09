# Definitions only. No deployment/database action.
function Assert-PaperLedgerPhase($Result,[string]$Phase,[string]$Schema) {
    if($Result.version -cne 'PAPER_APPLICATION_LEDGER_V1' -or $Result.status -cne 'ISOLATED_LEDGER_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong ledger phase identity/status.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw "Unsafe ledger flag: $flag"}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Synthetic write disclosure missing.'}
    $expected=if($Phase -ceq '--prepare'){@(
        'pristine_attachment_preserves_existing_cash','changed_cash_not_attached_or_reset','missing_account_not_reseeded','multiple_active_accounts_not_attached','legacy_history_blocks_attachment',
        'approval_reserves_without_debit','exact_command_retry_returns_original_receipt','conflicting_command_rolls_back','partial_fills_and_legacy_cash_are_atomic','fill_identity_cannot_debit_twice',
        'overfill_and_fee_overrun_rejected','cancellation_releases_remaining_cash','expiry_is_explicit_and_due','hold_records_decision_without_order','unowned_sell_rejected',
        'sell_reserves_owned_shares_and_partial_cancel_releases','stale_revision_rejected','rollback_after_projection_writes','lost_ack_exact_retry_is_idempotent','concurrent_approvals_serialize',
        'concurrent_duplicate_has_one_effect','lock_deadline_preserves_state','legacy_divergence_blocks','append_only_evidence_rejects_edit_and_delete','order_corruption_blocks','journal_projection_corruption_blocks',
        'more_than_256_commands_preserves_early_identity','prepare_restart_ledger'
    )}elseif($Phase -ceq '--recover'){@('fresh_jvm_recovery_preserves_balances','recovered_duplicate_does_not_debit','recovered_expiry_releases_reservation')}else{throw 'Unknown ledger phase.'}
    Assert-PaperExact $Result.checkCount $expected.Count 'checkCount';Assert-PaperExact $Result.failedCount 0 'failedCount'
    if(@($Result.checks).Count -ne $expected.Count){throw 'Missing ledger checks.'}
    foreach($name in $expected){$rows=@($Result.checks|Where-Object {$_.name -ceq $name});if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw "Ledger check absent/failed: $name"}}
    Assert-PaperExact $Result.cashPaise 9959990 'cashPaise'
    Assert-PaperExact $Result.reservedCashPaise $(if($Phase -ceq '--prepare'){60690}else{0}) 'reservedCashPaise'
    Assert-PaperExact $Result.revision $(if($Phase -ceq '--prepare'){2}else{3}) 'revision'
}
