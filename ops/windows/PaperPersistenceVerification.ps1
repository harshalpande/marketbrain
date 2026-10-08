# Definitions only. Independent fixed-fixture report review; no Docker or database calls on import.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalPaperPreparation.ps1')
function Assert-PaperPersistencePhase($Result,[string]$Phase,[string]$Schema) {
    if($Result.version -cne 'PAPER_PERSISTENCE_ENGINEERING_V1' -or $Result.status -cne 'ISOLATED_DATABASE_CHECKS_PASSED' -or $Result.phase -cne $Phase -or $Result.schema -cne $Schema){throw 'Wrong persistence result identity/status.'}
    foreach($flag in @('applicationDatabaseAccessed','runtimePaperAccountEnabled','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw "Unsafe flag: $flag"}}
    if($Result.syntheticDatabaseWritesPerformed -isnot [bool] -or -not $Result.syntheticDatabaseWritesPerformed){throw 'Missing synthetic database write disclosure.'}
    foreach($field in @('providerCallCount','modelCallCount','realOrdersCreated','failedCount')){Assert-PaperExact $Result.$field 0 $field}
    $expected=if($Phase -ceq '--prepare'){@('committed_approval_reopens_with_reservation','same_command_duplicate_no_revision_or_cash_change','conflicting_id_rejected_without_write','partial_fill_and_cancel_survive_reconstruction','duplicate_fill_different_command_does_not_debit','overfill_rolls_back_without_journal_append','transaction_failure_rolls_back_insert_and_projection','lost_commit_ack_retry_reconciles_once','terminated_backend_rolls_back_uncommitted_command','concurrent_approvals_cannot_double_spend','concurrent_same_id_has_one_commit','lock_timeout_fails_without_partial_write','tampered_projection_blocks_reopen','tampered_command_hash_blocks_reopen','missing_account_never_reseeds','changed_policy_blocks_replay','no_op_time_cannot_hide_clock_rollback','capacity_stops_without_evicting_ids','hold_persists_without_an_order','unowned_sell_rejected','prepare_restart_fixture')}elseif($Phase -ceq '--recover'){@('fresh_jvm_after_database_restart_reconciles','post_restart_duplicate_fill_has_no_effect','post_restart_expiry_releases_only_remaining_reservation')}else{throw 'Unknown phase.'}
    Assert-PaperExact $Result.checkCount $expected.Count 'check count'
    $names=@($Result.checks|ForEach-Object {$_.name})
    if((($names|Sort-Object) -join ',') -cne (($expected|Sort-Object) -join ',')){throw 'Incomplete or duplicate persistence checks.'}
    foreach($check in $Result.checks){if($check.passed -isnot [bool] -or -not $check.passed -or $check.failure){throw 'Failed persistence check.'};Assert-BaselineNumber $check.elapsedMillis ([double]$check.elapsedMillis) 'timing';if($check.elapsedMillis -lt 0){throw 'Negative timing.'}}
    $receipt=$Result.receipt;$audit=$receipt.audit;$a=$audit.account
    if($receipt.tailHash -cnotmatch '^[a-f0-9]{64}$' -or $receipt.duplicate -isnot [bool] -or $receipt.duplicate){throw 'Invalid receipt.'}
    $revision=if($Phase -ceq '--prepare'){7}else{8}
    Assert-PaperExact $receipt.revision $revision 'revision'
    Assert-PaperExact @($audit.journal).Count $revision 'journal count'
    $debit=[decimal]0;$credit=[decimal]0;$fees=[decimal]0;$quantity=[decimal]0;$index=0;$ids=@{}
    $kinds=@('APPROVED','BUY_FILL','BUY_FILL','APPROVED','SELL_FILL','CANCELLED','APPROVED');if($revision -eq 8){$kinds+='EXPIRED'}
    $orderIds=@('buy','buy','buy','sell','sell','sell','pending');if($revision -eq 8){$orderIds+='pending'}
    foreach($event in $audit.journal){
        Assert-PaperExact $event.sequence ($index+1) 'journal sequence'
        if($event.kind -cne $kinds[$index] -or $event.orderId -cne $orderIds[$index] -or $event.symbol -cne 'FIXTURE'){throw 'Unexpected journal identity/transition.'};$index++
        foreach($field in @('quantity','pricePaise','feePaise','debitPaise','creditPaise')){[void](Get-PaperExactInteger $event.$field $field)}
        if($event.kind -cin @('BUY_FILL','SELL_FILL')){
            if(-not $event.fillId -or $ids.ContainsKey($event.fillId)){throw 'Duplicate fill.'};$ids[$event.fillId]=$true
            $notional=[decimal]$event.quantity*[decimal]$event.pricePaise
            if($event.kind -ceq 'BUY_FILL'){Assert-PaperExact $event.debitPaise ($notional+$event.feePaise) 'buy amount';Assert-PaperExact $event.creditPaise 0 'buy credit';$quantity+=$event.quantity}
            else{Assert-PaperExact $event.creditPaise ($notional-$event.feePaise) 'sell amount';Assert-PaperExact $event.debitPaise 0 'sell debit';$quantity-=$event.quantity}
            $debit+=$event.debitPaise;$credit+=$event.creditPaise;$fees+=$event.feePaise
        }else{foreach($field in @('debitPaise','creditPaise','feePaise')){Assert-PaperExact $event.$field 0 'nonfill cash'}}
    }
    Assert-PaperExact $audit.initialCashPaise 10000000 'initial cash';Assert-PaperExact $audit.debitPaise $debit 'debits';Assert-PaperExact $audit.creditPaise $credit 'credits';Assert-PaperExact $audit.feesPaise $fees 'fees'
    Assert-PaperExact $a.cashPaise (10000000+$credit-$debit) 'cash conservation';Assert-PaperExact $a.cashPaise 9919970 'fixture cash';Assert-PaperExact $fees 30 'fixture fees'
    Assert-PaperExact $a.holdings.FIXTURE $quantity 'holding conservation';Assert-PaperExact $quantity 8 'fixture holding'
    Assert-PaperExact @($a.holdings.PSObject.Properties).Count 1 'holding names';Assert-PaperExact @($a.reservedShares.PSObject.Properties).Count 0 'sell reservation'
    Assert-PaperExact @($a.orders.PSObject.Properties).Count 3 'orders';Assert-PaperExact $a.approvalCount 3 'approvals';Assert-PaperExact $a.fillCount 3 'fills';Assert-PaperExact $audit.syntheticFillCount 3 'synthetic fills';Assert-PaperExact $audit.syntheticOrdersCreated 3 'synthetic orders'
    if($a.orders.buy.status -cne 'FILLED' -or $a.orders.sell.status -cne 'CANCELLED'){throw 'Unexpected terminal orders.'}
    Assert-PaperExact $a.orders.buy.filledQuantity 10 'bought';Assert-PaperExact $a.orders.sell.filledQuantity 2 'sold';Assert-PaperExact $a.orders.pending.filledQuantity 0 'unfilled'
    $reserved=if($Phase -ceq '--prepare'){if($a.orders.pending.status -cne 'OPEN'){throw 'Pending order missing'};([decimal]$a.orders.pending.approval.quantity*$a.orders.pending.approval.zoneMaxPaise)+$a.orders.pending.approval.feeBudgetPaise}else{if($a.orders.pending.status -cne 'EXPIRED'){throw 'Expiry missing'};0}
    Assert-PaperExact $a.reservedCashPaise $reserved 'reserved cash';Assert-PaperExact $a.availableCashPaise ([decimal]$a.cashPaise-$reserved) 'available cash'
}
