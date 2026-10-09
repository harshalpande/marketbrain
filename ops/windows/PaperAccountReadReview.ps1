# Definitions only. No service, Docker, database or credential access on import.
Set-StrictMode -Version Latest
function Assert-PaperAccountOverview($Value) {
    if ($Value.version -cne 'PAPER_ACCOUNT_OVERVIEW_V1' -or $Value.status -cne 'READ_ONLY_EXECUTION_BLOCKED' -or $Value.currency -cne 'INR') { throw 'Unexpected account contract.' }
    foreach ($name in @('databaseWritesPerformed','actionExecutionEnabled','liveExecutionEnabled')) {
        if ($Value.$name -isnot [bool] -or $Value.$name) { throw "Unsafe or missing flag: $name" }
    }
    if (($Value.activeAccountsObserved -isnot [int] -and $Value.activeAccountsObserved -isnot [long]) -or $Value.activeAccountsObserved -notin @(0,1,2)) { throw 'Invalid account count.' }
    foreach ($name in @('activeAccountCountIsLowerBound','legacyOrdersPresent','legacyFillsPresent')) {
        if ($Value.$name -isnot [bool]) { throw "Missing boolean: $name" }
    }
    if ($Value.activeAccountCountIsLowerBound -ne ($Value.activeAccountsObserved -eq 2)) { throw 'Invalid count bound.' }
    if (($Value.activeAccountsObserved -eq 1) -ne ($null -ne $Value.account)) { throw 'Ambiguous account selection.' }
    if ($Value.migrationAssessment -cnotin @('EMPTY_ACCOUNT_REVIEWABLE','REVIEW_REQUIRED')) { throw 'Unknown migration state.' }
    foreach ($blocker in @('APPLICATION_LEDGER_MIGRATION_PENDING','AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING')) {
        if ($blocker -cnotin @($Value.blockers)) { throw 'Missing release gate.' }
    }
    [void][DateTimeOffset]::Parse($Value.observedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $Value.account) {
        if ($Value.account.id -isnot [string] -or $Value.account.id -notmatch '^[1-9][0-9]*$') { throw 'Invalid account identity.' }
        foreach ($name in @('startingCash','currentCash')) {
            if ($Value.account.$name -isnot [string] -or $Value.account.$name -notmatch '^[0-9]{1,16}(\.[0-9]{1,2})?$') { throw 'Invalid monetary string.' }
        }
    }
}
