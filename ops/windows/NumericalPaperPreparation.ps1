# Offline independent review only. No application/provider/DB access.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1')
function Get-PaperExactInteger($Value,[string]$Name) {
    if($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64] -and $Value -isnot [decimal] -and $Value -isnot [double]){throw "Non-numeric $Name"}
    if([double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value)){throw "Non-finite $Name"}
    $n=[decimal]$Value
    if($n -lt 0 -or $n -gt 1000000000000 -or [decimal]::Truncate($n) -ne $n){throw "Invalid bounded integer $Name"}
    return $n
}
function Assert-PaperExact($Actual,$Expected,[string]$Name) {
    if((Get-PaperExactInteger $Actual $Name) -ne [decimal]$Expected){throw "Paper arithmetic mismatch: $Name"}
}
function Assert-PilotPolicyReview($PolicyReview) {
    if($PolicyReview.version -cne 'NUMERICAL_PILOT_POLICY_REVIEW_V1' -or $PolicyReview.status -cne 'DRAFT_CONSISTENCY_PASSED_NOT_APPROVED' -or
       $PolicyReview.failedCount -ne 0 -or $PolicyReview.checkCount -ne @($PolicyReview.checks).Count -or $PolicyReview.passedCount -ne $PolicyReview.checkCount -or $PolicyReview.checkCount -ne 29){throw 'Draft policy consistency review failed.'}
    foreach($flag in @('trainingAuthorized','collectionAuthorized')){if($PolicyReview.$flag -isnot [bool] -or $PolicyReview.$flag){throw 'Policy review incorrectly authorizes runtime.'}}
    foreach($check in $PolicyReview.checks){if($check.passed -isnot [bool] -or -not $check.passed -or $check.failure){throw 'Failed policy check.'}}
    $p=$PolicyReview.proposal
    if($p.status -cne 'DRAFT_OWNER_REVIEW' -or $p.runtimeConfiguration -isnot [bool] -or $p.runtimeConfiguration -or $p.approvedByOwner -isnot [bool] -or $p.approvedByOwner){throw 'Proposal is not an unapproved nonruntime draft.'}
    foreach($key in @('collectionAuthorized','marketFitAuthorized','finalTestOpeningAuthorized','providerCallsAuthorized','modelPromotionAuthorized','paperExecutionAuthorized','liveExecutionAuthorized')){if($p.release.$key -isnot [bool] -or $p.release.$key){throw 'Proposal execution gate changed.'}}
}
function Assert-NumericalPaperPreparation($Result,$PolicyReview) {
    Assert-PilotPolicyReview $PolicyReview
    if($Result.version -cne 'PAPER_ACCOUNT_ENGINEERING_V1' -or $Result.status -cne 'ENGINEERING_CHECKS_PASSED' -or $Result.syntheticOnly -isnot [bool] -or -not $Result.syntheticOnly){throw 'Wrong paper fixture result.'}
    foreach($flag in @('runtimePaperAccountEnabled','databaseWritesPerformed','actionExecutionEnabled')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw "Unsafe paper flag: $flag"}}
    foreach($key in @('providerCallCount','modelCallCount','ordersCreated','signalsCreated','failedCount')){Assert-PaperExact $Result.$key 0 $key}
    Assert-PaperExact $Result.initialCashPaise 10000000 'initial cash'
    $names=@('initial_capital_exact','hold_creates_no_order','buy_reserves_cash_and_costs','duplicate_approval_no_double_reservation',
        'approval_id_conflict_rejected','cash_cannot_be_double_reserved','partial_buy_reconciles_reservation','duplicate_fill_no_double_debit',
        'fill_id_conflict_rejected','sell_requires_owned_shares','sell_cannot_double_reserve_shares','partial_sell_reconciles_net_proceeds',
        'cancel_releases_only_unfilled_reservation','expiry_releases_reservation','expired_order_cannot_fill','stale_and_future_quotes_rejected',
        'out_of_zone_buy_not_chased','slippage_guard_independent_of_zone','risk_revalidated_at_fill','optimistic_fill_rejected',
        'fee_overrun_rejected_atomically','overfill_rejected','overflow_rejected_before_mutation','clock_rollback_blocks_mutation',
        'terminal_order_not_reopened','bounded_account_no_implicit_eviction')
    if($Result.checkCount -ne $names.Count -or @($Result.checks).Count -ne $names.Count){throw 'Incomplete paper test suite.'}
    $seen=@{}
    foreach($check in $Result.checks){
        if($names -cnotcontains $check.name -or $seen.ContainsKey($check.name) -or $check.passed -isnot [bool] -or -not $check.passed -or $check.failure){throw 'Failed/missing/duplicate paper check.'}
        $seen[$check.name]=$true;Assert-BaselineNumber $check.elapsedMillis ([double]$check.elapsedMillis) 'paper check timing'
        if($check.elapsedMillis -lt 0){throw 'Negative timing.'}
    }
    $e=$Result.accountingEvidence;$a=$e.account
    Assert-PaperExact $e.initialCashPaise 10000000 'audit initial cash'
    $debits=[decimal]0;$credits=[decimal]0;$fees=[decimal]0;$owned=@{};$fills=@{};$fillIds=@{};$states=@{};$events=0;$lastAt=$null
    foreach($event in $e.journal){
        $events++;Assert-PaperExact $event.sequence $events 'journal sequence'
        $at=ConvertTo-TenFeatureUtc $event.at;if($null -ne $lastAt -and $at -lt $lastAt){throw 'Journal clock rollback.'};$lastAt=$at
        foreach($field in @('quantity','pricePaise','feePaise','debitPaise','creditPaise')){[void](Get-PaperExactInteger $event.$field "event.$field")}
        $orderProperty=$a.orders.PSObject.Properties[$event.orderId]
        if($null -eq $orderProperty){throw 'Journal references absent fixture order.'}
        $eventOrder=$orderProperty.Value
        if($event.symbol -cne $eventOrder.approval.symbol){throw 'Journal instrument mismatch.'}
        if($event.kind -cin @('BUY_FILL','SELL_FILL')){
            if(-not $states.ContainsKey($event.orderId) -or $states[$event.orderId] -cnotin @('OPEN','PARTIAL')){throw 'Fill without active approval.'}
            if($event.kind -cne ($eventOrder.approval.side+'_FILL')){throw 'Fill side mismatch.'}
            if($at -lt (ConvertTo-TenFeatureUtc $eventOrder.approvedAt) -or $at -ge (ConvertTo-TenFeatureUtc $eventOrder.approval.expiresAt)){throw 'Fill outside approval window.'}
            if(-not $event.fillId -or $fillIds.ContainsKey($event.fillId)){throw 'Duplicate or missing fill identity.'};$fillIds[$event.fillId]=$true
            if(-not $fills.ContainsKey($event.orderId)){$fills[$event.orderId]=@{quantity=[decimal]0;fees=[decimal]0}}
            if(-not $owned.ContainsKey($event.symbol)){$owned[$event.symbol]=[decimal]0}
            $q=Get-PaperExactInteger $event.quantity 'fill quantity';$price=Get-PaperExactInteger $event.pricePaise 'fill price'
            if($q -le 0 -or $price -le 0){throw 'Empty fill.'}
            $notional=$q*$price;$fee=Get-PaperExactInteger $event.feePaise 'fill fee'
            if($event.kind -ceq 'BUY_FILL'){
                Assert-PaperExact $event.debitPaise ($notional+$fee) 'buy debit';Assert-PaperExact $event.creditPaise 0 'buy credit';$owned[$event.symbol]+=$q
            } else {
                if($fee -gt $notional){throw 'Fee exceeds proceeds.'}
                Assert-PaperExact $event.creditPaise ($notional-$fee) 'sell credit';Assert-PaperExact $event.debitPaise 0 'sell debit';$owned[$event.symbol]-=$q
                if($owned[$event.symbol] -lt 0){throw 'Journal oversell.'}
            }
            $debits+=[decimal]$event.debitPaise;$credits+=[decimal]$event.creditPaise;$fees+=$fee
            $fills[$event.orderId].quantity+=$q;$fills[$event.orderId].fees+=$fee
            $states[$event.orderId]=if($fills[$event.orderId].quantity -eq $eventOrder.approval.quantity){'FILLED'}else{'PARTIAL'}
        } else {
            if($event.kind -cnotin @('APPROVED','HOLD_NO_ORDER','CANCELLED','EXPIRED')){throw 'Unknown journal event.'}
            foreach($field in @('debitPaise','creditPaise','feePaise')){Assert-PaperExact $event.$field 0 'non-fill cash movement'}
            if($event.kind -ceq 'APPROVED'){
                if($states.ContainsKey($event.orderId) -or $at -ne (ConvertTo-TenFeatureUtc $eventOrder.approvedAt)){throw 'Duplicate or mistimed approval.'}
                Assert-PaperExact $event.quantity $eventOrder.approval.quantity 'approved quantity';$states[$event.orderId]='OPEN'
            } elseif($event.kind -cin @('CANCELLED','EXPIRED')){
                if(-not $states.ContainsKey($event.orderId) -or $states[$event.orderId] -cnotin @('OPEN','PARTIAL')){throw 'Invalid terminal transition.'}
                $states[$event.orderId]=$event.kind
            } else {throw 'Unexpected HOLD in fixed accounting trace.'}
        }
    }
    Assert-PaperExact $e.debitPaise $debits 'total debit';Assert-PaperExact $e.creditPaise $credits 'total credit';Assert-PaperExact $e.feesPaise $fees 'total fees'
    Assert-PaperExact $a.cashPaise (10000000+$credits-$debits) 'cash conservation'
    if((@($a.holdings.PSObject.Properties|ForEach-Object {$_.Name}|Sort-Object) -join ',') -cne (@($owned.Keys|Sort-Object) -join ',')){throw 'Holdings identities differ.'}
    foreach($symbol in $owned.Keys){Assert-PaperExact $a.holdings.$symbol $owned[$symbol] 'holding conservation'}
    $reserved=[decimal]0;$reservedShares=@{};$orderCount=0
    foreach($prop in $a.orders.PSObject.Properties){
        $orderCount++;$o=$prop.Value;$p=$o.approval
        if($p.orderId -cne $prop.Name -or $p.side -cnotin @('BUY','SELL')){throw 'Wrong order identity/side.'}
        if(-not $states.ContainsKey($prop.Name) -or $states[$prop.Name] -cne $o.status){throw 'Final order status differs from journal.'}
        $filled=[decimal]0;$paid=[decimal]0;if($fills.ContainsKey($prop.Name)){$filled=$fills[$prop.Name].quantity;$paid=$fills[$prop.Name].fees}
        Assert-PaperExact $o.filledQuantity $filled 'order filled quantity';Assert-PaperExact $o.feesPaidPaise $paid 'order fees'
        $quantity=Get-PaperExactInteger $p.quantity 'order quantity';$budget=Get-PaperExactInteger $p.feeBudgetPaise 'fee budget'
        if($filled -gt $quantity -or $paid -gt $budget){throw 'Overfill or fee overrun.'}
        if($o.status -cin @('OPEN','PARTIAL')){
            if($filled -ge $quantity -or ($o.status -ceq 'OPEN' -and $filled -ne 0) -or ($o.status -ceq 'PARTIAL' -and $filled -eq 0)){throw 'Active order fill-state mismatch.'}
            if($p.side -ceq 'BUY'){$reserved+=($quantity-$filled)*(Get-PaperExactInteger $p.zoneMaxPaise 'zone max')+$budget-$paid}
            else{if(-not $reservedShares.ContainsKey($p.symbol)){$reservedShares[$p.symbol]=[decimal]0};$reservedShares[$p.symbol]+=$quantity-$filled}
        } elseif($o.status -ceq 'FILLED'){if($filled -ne $quantity){throw 'Incomplete filled order.'}}
        elseif($o.status -cnotin @('CANCELLED','EXPIRED')){throw 'Unknown terminal state.'}
    }
    if((@($a.reservedShares.PSObject.Properties|ForEach-Object {$_.Name}|Sort-Object) -join ',') -cne (@($reservedShares.Keys|Sort-Object) -join ',')){throw 'Reserved-share identities differ.'}
    foreach($symbol in $reservedShares.Keys){Assert-PaperExact $a.reservedShares.$symbol $reservedShares[$symbol] 'share reservations';if($reservedShares[$symbol] -gt $owned[$symbol]){throw 'Oversold reservation.'}}
    Assert-PaperExact $a.reservedCashPaise $reserved 'cash reservation'
    Assert-PaperExact $a.availableCashPaise ([decimal]$a.cashPaise-$reserved) 'available cash'
    Assert-PaperExact $e.syntheticOrdersCreated $orderCount 'synthetic orders';Assert-PaperExact $e.syntheticFillCount $fillIds.Count 'synthetic fills'
    Assert-PaperExact $a.fillCount $fillIds.Count 'account fill count'
    # This fixed trace must retain the sold quantity, cancellation and unfilled reservation, not just conserved totals.
    Assert-PaperExact $orderCount 3 'fixture order count';Assert-PaperExact $fillIds.Count 3 'fixture fill count'
    Assert-PaperExact $a.cashPaise 9919970 'fixture ending cash';Assert-PaperExact $a.reservedCashPaise 20300 'fixture reservation'
    Assert-PaperExact $a.holdings.FIXTURE 8 'fixture holding';if($a.orders.sell.status -cne 'CANCELLED'){throw 'Missing fixture cancellation.'}
}
