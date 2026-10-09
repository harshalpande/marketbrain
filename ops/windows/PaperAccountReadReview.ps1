# Definitions only. No service, Docker, database or credential access on import.
Set-StrictMode -Version Latest
function Assert-PaperAccountOverview($Value,[switch]$AllowV1) {
    $versions=@('PAPER_ACCOUNT_OVERVIEW_V2');if($AllowV1){$versions+= 'PAPER_ACCOUNT_OVERVIEW_V1'}
    if ($Value.version -cnotin $versions -or $Value.status -cne 'READ_ONLY_EXECUTION_BLOCKED' -or $Value.currency -cne 'INR') { throw 'Unexpected account contract.' }
    foreach ($name in @('databaseWritesPerformed','actionExecutionEnabled','liveExecutionEnabled')) {
        if ($Value.$name -isnot [bool] -or $Value.$name) { throw "Unsafe or missing flag: $name" }
    }
    if (($Value.activeAccountsObserved -isnot [int] -and $Value.activeAccountsObserved -isnot [long]) -or $Value.activeAccountsObserved -notin @(0,1,2)) { throw 'Invalid account count.' }
    foreach ($name in @('activeAccountCountIsLowerBound','legacyOrdersPresent','legacyFillsPresent')) {
        if ($Value.$name -isnot [bool]) { throw "Missing boolean: $name" }
    }
    if ($Value.activeAccountCountIsLowerBound -ne ($Value.activeAccountsObserved -eq 2)) { throw 'Invalid count bound.' }
    if (($Value.activeAccountsObserved -eq 1) -ne ($null -ne $Value.account)) { throw 'Ambiguous account selection.' }
    if ($Value.migrationAssessment -cnotin @('EMPTY_ACCOUNT_REVIEWABLE','REVIEW_REQUIRED','LEDGER_ATTACHED_READ_ONLY')) { throw 'Unknown migration state.' }
    foreach ($blocker in @('AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING')) {
        if ($blocker -cnotin @($Value.blockers)) { throw 'Missing release gate.' }
    }
    [void][DateTimeOffset]::Parse($Value.observedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $Value.account) {
        if ($Value.account.id -isnot [string] -or $Value.account.id -notmatch '^[1-9][0-9]*$') { throw 'Invalid account identity.' }
        foreach ($name in @('startingCash','currentCash')) {
            if ($Value.account.$name -isnot [string] -or $Value.account.$name -notmatch '^[0-9]{1,16}(\.[0-9]{1,2})?$') { throw 'Invalid monetary string.' }
        }
    }
    if($Value.version -ceq 'PAPER_ACCOUNT_OVERVIEW_V1') {
        if($Value.migrationAssessment -ceq 'LEDGER_ATTACHED_READ_ONLY' -or 'APPLICATION_LEDGER_MIGRATION_PENDING' -cnotin @($Value.blockers)){throw 'Invalid legacy migration state.'}
    } else { Assert-PaperLedgerRead $Value }
}
function Assert-PaperLedgerRead($Value) {
    $l=$Value.ledger
    if($null -eq $l -or $l.status -cnotin @('NOT_ATTACHED','REVIEW_REQUIRED','ATTACHED_READ_ONLY')){throw 'Invalid ledger state.'}
    if($l.status -ceq 'ATTACHED_READ_ONLY') {
        if($null -eq $Value.account -or $Value.account.id -cne '1' -or $Value.account.name -cne 'Default Paper Portfolio' -or $Value.account.executionMode -cne 'PAPER' -or $Value.account.startingCash -cne '100000.00' -or $Value.account.currentCash -cne '100000.00' -or $Value.legacyOrdersPresent -or $Value.legacyFillsPresent){throw 'Attached account differs from reviewed baseline.'}
        if($Value.migrationAssessment -cne 'LEDGER_ATTACHED_READ_ONLY' -or $l.cash -cne '100000.00' -or $l.reservedCash -cne '0.00' -or $l.unreservedCash -cne '100000.00' -or $l.revision -cne '0'){throw 'Invalid opening ledger projection.'}
        foreach($name in @('cash','reservedCash','unreservedCash','revision')){if($l.$name -isnot [string]){throw 'Ledger values must be exact strings.'}}
        if('APPLICATION_LEDGER_MIGRATION_PENDING' -cin @($Value.blockers) -or 'LEDGER_RECONCILIATION_REQUIRED' -cin @($Value.blockers)){throw 'Inconsistent attachment gates.'}
    } else {
        foreach($name in @('cash','reservedCash','unreservedCash','revision')){if($null -ne $l.$name){throw 'Unverified ledger amounts must be withheld.'}}
        $gate=if($l.status -ceq 'NOT_ATTACHED'){'APPLICATION_LEDGER_MIGRATION_PENDING'}else{'LEDGER_RECONCILIATION_REQUIRED'}
        if($gate -cnotin @($Value.blockers) -or $Value.migrationAssessment -ceq 'LEDGER_ATTACHED_READ_ONLY'){throw 'Inconsistent ledger gates.'}
    }
}
function Assert-PaperAttachmentPreflight($Value) {
    Assert-PaperAccountOverview $Value -AllowV1
    if($null -eq $Value.account -or $Value.account.id -cne '1' -or $Value.account.name -cne 'Default Paper Portfolio' -or $Value.account.executionMode -cne 'PAPER' -or $Value.account.startingCash -cne '100000.00' -or $Value.account.currentCash -cne '100000.00' -or $Value.legacyOrdersPresent -or $Value.legacyFillsPresent -or $Value.migrationAssessment -cnotin @('EMPTY_ACCOUNT_REVIEWABLE','LEDGER_ATTACHED_READ_ONLY')){throw 'Account is not the reviewed pristine baseline. No deployment permitted.'}
}
