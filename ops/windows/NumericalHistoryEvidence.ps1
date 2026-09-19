# Definitions only; validation does not invoke the service.
Set-StrictMode -Version Latest
function Invoke-HistoryAtomicReplace([string]$Temporary,[string]$Path) {
    [IO.File]::Replace($Temporary,$Path,[System.Management.Automation.Language.NullString]::Value)
}
function Save-NumericalHistoryReport($Report,[string]$Path,[switch]$Compact,[ValidateRange(1,20)][int]$MaxReplaceAttempts=6) {
    $Report.updatedAtUtc=[DateTime]::UtcNow.ToString('o')
    $temporary=$Path+'.pending-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($Report | ConvertTo-Json -Depth 16 -Compress:$Compact),[Text.UTF8Encoding]::new($false))
    for($attempt=1;$attempt -le $MaxReplaceAttempts;$attempt++) {
        try {
            if([IO.File]::Exists($Path)){Invoke-HistoryAtomicReplace $temporary $Path}
            else{[IO.File]::Move($temporary,$Path)}
            return
        } catch {
            $cause=$_.Exception
            while($cause.InnerException){$cause=$cause.InnerException}
            # Brief Windows sharing/lock violations only; never retry collection or delete old evidence.
            if($cause -isnot [IO.IOException] -or ($cause.HResult -band 65535) -notin @(32,33) -or $attempt -eq $MaxReplaceAttempts){throw}
            Start-Sleep -Milliseconds (100*$attempt)
        }
    }
}
function Assert-NumericalHistoryPage($Page,[guid]$RunId,[int]$Offset,[int]$LookbackDays,[string]$Manifest,[int]$ExpectedCount=0) {
    foreach($field in @('offset','limit','lookbackDays','instrumentCount')) {
        if($Page.$field -isnot [int] -and $Page.$field -isnot [long]){throw 'Non-integer page count.'}
    }
    $asOf=[datetime]::ParseExact([string]$Page.asOf,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    $from=[datetime]::ParseExact([string]$Page.windowFrom,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
    if(($asOf-$from).Days -ne ($LookbackDays-1)){throw 'Incorrect coverage window.'}
    if ($Page.version -ne 'NUMERICAL_HISTORY_COVERAGE_V1' -or $Page.status -ne 'REVIEW_REQUIRED' -or
        [string]$Page.datasetRunId -ne $RunId.ToString() -or $Page.offset -ne $Offset -or
        $Page.limit -ne 50 -or $Page.lookbackDays -ne $LookbackDays -or
        $Page.instrumentCount -lt 1 -or $Page.instrumentCount -gt 500 -or
        $Page.datasetManifestHash -notmatch '^[a-fA-F0-9]{64}$') {throw 'Unexpected history page contract or scope.'}
    if ($Manifest -and $Manifest -ne $Page.datasetManifestHash) {throw 'Manifest changed between pages.'}
    if ($ExpectedCount -gt 0 -and $ExpectedCount -ne $Page.instrumentCount) {throw 'Instrument count changed between pages.'}
    foreach($flag in @('databaseWritesPerformed')) {if($Page.$flag -isnot [bool] -or $Page.$flag){throw 'Read-only flag invalid.'}}
    foreach($field in @('modelCallCount','providerCallCount','ordersCreated')) {if($null -eq $Page.$field -or $Page.$field -is [string] -or $Page.$field -is [bool] -or $Page.$field -ne 0){throw 'Unexpected side-effect counter.'}}
    if($Page.contract.version -ne 'NUMERICAL_SWING_20_V1_DRAFT' -or $Page.contract.trainingAuthorized -isnot [bool] -or $Page.contract.trainingAuthorized){throw 'Unexpected training authorization/contract.'}
    if($Page.partial -isnot [bool]){throw 'Missing partial flag.'}
    $items=@($Page.instruments)
    if($items.Count -ne [math]::Min(50,$Page.instrumentCount-$Offset)){throw 'Incomplete page; retain partial evidence.'}
    $next=$Offset+$items.Count
    if(($next -lt $Page.instrumentCount -and $Page.nextOffset -ne $next) -or ($next -eq $Page.instrumentCount -and $null -ne $Page.nextOffset)){throw 'Invalid next offset; refusing loop.'}
    foreach($item in $items) {
        foreach($field in @('rawRowsScanned','observedDates','nonexcludedDates','excludedDates','receivedAfterDecisionCutoffRows','missingReceivedAtRows','nseRows','upstoxRows')) {
            if(($item.$field -isnot [int] -and $item.$field -isnot [long]) -or $item.$field -lt 0 -or $item.$field -gt 2001){throw 'Invalid integer coverage count.'}
        }
        if([string]$item.instrumentId -notmatch '^[1-9][0-9]*$' -or [string]::IsNullOrWhiteSpace($item.symbol)){throw 'Invalid instrument identity.'}
        if($item.rawRowsScanned -lt 0 -or $item.rawRowsScanned -gt 2001 -or $item.observedDates -gt $item.rawRowsScanned -or
            $item.nonexcludedDates -gt $item.observedDates -or $item.nonexcludedDates -lt 0){throw 'Invalid coverage counts.'}
        if(($item.nseRows+$item.upstoxRows) -ne $item.rawRowsScanned -or
            ($item.excludedDates+$item.nonexcludedDates) -ne $item.observedDates -or
            ($item.receivedAfterDecisionCutoffRows+$item.missingReceivedAtRows) -gt $item.rawRowsScanned){throw 'Coverage totals inconsistent.'}
        if($item.truncated -isnot [bool] -or $item.truncated -ne ($item.rawRowsScanned -gt 2000)){throw 'Truncation flag/count mismatch.'}
    }
    if($Page.partial -ne (@($items | Where-Object truncated).Count -gt 0)){throw 'Page partial flag inconsistent.'}
}
