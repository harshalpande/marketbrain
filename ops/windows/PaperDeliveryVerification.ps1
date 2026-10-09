# Definition only. Exact-case validation independent of fixture output.
function Assert-PaperDeliveryPhase($Result,[string]$Phase,[string]$Schema){
    if($Result.version -cne 'PAPER_DELIVERY_REVIEW_V1' -or $Result.status -cne 'ISOLATED_DELIVERY_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema -or $Result.httpTransport -cne 'FAKE_NO_NETWORK'){throw 'Wrong delivery phase identity or transport.'}
    foreach($flag in @('applicationDatabaseAccessed','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw "Unsafe delivery flag: $flag"}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Synthetic write disclosure missing.'}
    foreach($counter in @('providerCalls','telegramCalls','modelCalls','orderCount','fillCount','ledgerRevision','reservedCashPaise','failedCount')){Assert-PaperExact $Result.$counter 0 $counter}
    Assert-PaperExact $Result.cashPaise 10000000 'cashPaise';Assert-PaperExact $Result.decisionCount 1 'decisionCount'
    Assert-PaperExact $Result.deliveryCount 3 'deliveryCount';Assert-PaperExact $Result.uncertainCount 1 'uncertainCount'
    $expected=if($Phase -ceq '--prepare'){@(
        'enqueue_commits_proposal_tokens_and_delivery_together','enqueue_replay_keeps_original_tokens','conflicting_publication_identity_rejected',
        'outbox_insert_failure_rolls_back_proposal_and_tokens','concurrent_enqueue_has_one_durable_publication','revoked_recipient_cannot_enqueue',
        'acknowledged_delivery_is_not_resent','concurrent_dispatch_claims_one_send','expired_delivery_never_sends','revoked_binding_before_dispatch_never_sends',
        'wrong_key_blocks_without_sending_or_token_reissue','lost_acknowledgement_is_uncertain_and_not_resent','sending_after_crash_is_not_automatically_retried',
        'sent_evidence_and_ciphertext_are_immutable','delivered_accept_runs_quote_adapter_and_review_only','delivered_reject_makes_no_quote_request',
        'wrong_provider_instrument_has_no_fallback','disabled_provider_mapping_blocks_quote_call','fresh_snapshot_with_old_trade_is_blocked',
        'callback_retry_after_ack_failure_reuses_receipt','prepare_delivery_restart_fixture'
    )}elseif($Phase -ceq '--recover'){@('restart_pending_delivery_can_send_once','restart_sent_and_uncertain_are_not_resent','restart_review_and_account_remain_unchanged')}else{throw 'Unknown delivery phase.'}
    Assert-PaperExact $Result.pendingCount $(if($Phase -ceq '--prepare'){1}else{0}) 'pendingCount'
    Assert-PaperExact $Result.checkCount $expected.Count 'checkCount'
    if(@($Result.checks).Count -ne $expected.Count){throw 'Missing delivery checks.'}
    foreach($name in $expected){$rows=@($Result.checks|Where-Object {$_.name -ceq $name});if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw "Delivery check absent/failed: $name"};Assert-PaperApprovalTiming $rows[0].elapsedMillis}
    Assert-PaperApprovalTiming $Result.elapsedSeconds
}
