# Definitions only. Independent exact-case verification; no database/runtime work on import.
function Assert-PaperApprovalPhase($Result,[string]$Phase,[string]$Schema) {
    if($Result.version -cne 'PAPER_APPROVAL_REVIEW_V1' -or $Result.status -cne 'ISOLATED_APPROVAL_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong approval phase identity/status.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw "Unsafe approval flag: $flag"}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Synthetic write disclosure missing.'}
    foreach($counter in @('providerCalls','telegramCalls','modelCalls','orderCount','fillCount','ledgerRevision','reservedCashPaise')){Assert-PaperExact $Result.$counter 0 $counter}
    Assert-PaperExact $Result.cashPaise 10000000 'cashPaise';Assert-PaperExact $Result.decisionCount 1 'decisionCount'
    $expected=if($Phase -ceq '--prepare'){@(
        'tokens_are_distinct_and_only_hashes_in_approval_tables','accept_records_review_without_order_or_reservation','reject_needs_no_quote_and_is_terminal',
        'unknown_token_never_fetches_quote','wrong_user_never_consumes_or_fetches','wrong_chat_never_fetches','nonprivate_callback_never_fetches',
        'expired_token_is_terminal_without_quote','stale_quote_is_not_retried_into_acceptance','future_quote_is_blocked','wrong_instrument_quote_is_blocked',
        'wrong_provider_quote_is_blocked','outside_zone_buy_is_not_chased','insufficient_cash_is_blocked','unowned_sell_is_blocked',
        'account_change_during_quote_invalidates_acceptance','binding_revocation_during_quote_prevents_consumption','changed_policy_is_blocked',
        'reused_policy_id_with_changed_limits_is_blocked','corrupted_account_projection_prevents_acceptance',
        'duplicate_after_expiry_returns_original_receipt','opposite_action_cannot_reverse_decision','concurrent_duplicate_records_one_receipt',
        'callback_id_conflict_rolls_back_second_decision','proposal_and_receipt_are_immutable','hold_cannot_issue_action_tokens','missing_ledger_never_reseeds',
        'quote_failure_is_recorded_without_retry','expiry_while_fetching_quote_is_rechecked','prepare_restart_receipt'
    )}elseif($Phase -ceq '--recover'){@('restart_duplicate_returns_saved_receipt_without_quote','restart_preserves_account_and_no_orders')}else{throw 'Unknown approval phase.'}
    Assert-PaperExact $Result.checkCount $expected.Count 'checkCount';Assert-PaperExact $Result.failedCount 0 'failedCount'
    if(@($Result.checks).Count -ne $expected.Count){throw 'Missing approval checks.'}
    foreach($name in $expected){$rows=@($Result.checks|Where-Object {$_.name -ceq $name});if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw "Approval check absent/failed: $name"}
        Assert-PaperApprovalTiming $rows[0].elapsedMillis
    }
    Assert-PaperApprovalTiming $Result.elapsedSeconds
}
function Assert-PaperApprovalTiming($Value){
    if($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or -not ($Value -is [ValueType])){throw 'Numeric timing required.'}
    $number=[double]$Value
    if([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0){throw 'Invalid timing.'}
}
