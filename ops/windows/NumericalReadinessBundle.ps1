# Pure bounded review of saved artifacts. No network, database, model or trading calls.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')

function Read-NumericalBundleInput([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 16MB){throw 'Regular JSON file <=16 MiB required.'}
    $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -gt 16MB){throw 'Input exceeds byte limit.'}
        $buffer=[IO.MemoryStream]::new()
        try{$stream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$buffer.Dispose()}
    }finally{$stream.Dispose()}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
    [pscustomobject]@{name=$file.Name;sha256=$hash;data=([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json)}
}

function Test-NumericalBundleNumber($Value) {
    if($null -eq $Value -or $Value -is [bool] -or $Value -is [string]){return $false}
    try { $n=[decimal]$Value;return $true } catch { return $false }
}

function Get-NumericalLabelPreflight([string]$DecisionDate,[string[]]$Sessions,$Bars) {
    # Deliberately not a certified label: stored prices have not been bound to executable prices.
    $index=[array]::IndexOf($Sessions,$DecisionDate)
    if($index -lt 0){throw 'Decision absent from reviewed calendar.'}
    $entry=$null;$exit=$null;$problem=$null;$gross=$null;$costs=@();$ids=@()
    $status='CALENDAR_HORIZON_UNAVAILABLE'
    if($index+1 -lt $Sessions.Count){$entry=$Sessions[$index+1]}
    if($index+20 -lt $Sessions.Count){
        $exit=$Sessions[$index+20];$status='STORED_PRICE_ARITHMETIC_ONLY'
        $byDate=@{};foreach($bar in $Bars){$byDate[[string]$bar.date]=$bar}
        for($i=$index+1;$i -le $index+20;$i++){
            $day=$Sessions[$i]
            if(-not $byDate.ContainsKey($day)){$status='MISSING_BAR';$problem=$day;break}
            $bar=$byDate[$day]
            if($bar.excluded){$status='EXCLUDED_BAR';$problem=$day;break}
            $valid=$true
            foreach($field in @('open','high','low','close')){
                if(-not(Test-NumericalBundleNumber $bar.$field) -or [decimal]$bar.$field -le 0){$valid=$false;break}
            }
            if($valid){$valid=([decimal]$bar.low -le [decimal]$bar.open -and [decimal]$bar.low -le [decimal]$bar.close -and [decimal]$bar.high -ge [decimal]$bar.open -and [decimal]$bar.high -ge [decimal]$bar.close)}
            if(-not $valid){$status='INVALID_OHLC';$problem=$day;break}
        }
        if($status -eq 'STORED_PRICE_ARITHMETIC_ONLY'){
            $ids=@(for($i=$index+1;$i -le $index+20;$i++){$byDate[$Sessions[$i]].candleId})
            $ratio=[math]::Round(([decimal]$byDate[$exit].close/[decimal]$byDate[$entry].open),16,[MidpointRounding]::AwayFromZero)
            $gross=[math]::Round((($ratio-1)*100),8,[MidpointRounding]::AwayFromZero)
            $costs=@(foreach($bps in @(0,25,50,100)){[pscustomobject]@{assumedRoundTripCostBps=$bps;indicativeNetPercent=($gross-[decimal]$bps/100)}})
        }
    }
    [pscustomobject]@{
        decisionDate=$DecisionDate;status=$status;entryDate=$entry;exitDate=$exit;problemDate=$problem
        sourceCandleIds=$ids;indicativeGrossPercent=$gross;costSensitivity=$costs
        executablePricesVerified=$false;corporateActionsApplied=$false;trainingAuthorized=$false
    }
}

function Get-NumericalSplitPreflight($Rows,[string]$ValidationFrom,[string]$TestFrom) {
    [void](ConvertTo-NumericalCalendarDate $ValidationFrom);[void](ConvertTo-NumericalCalendarDate $TestFrom)
    if($ValidationFrom -ge $TestFrom){throw 'Split boundaries must ascend.'}
    $seen=[Collections.Generic.HashSet[string]]::new()
    $assignments=@(foreach($row in $Rows){
        [void](ConvertTo-NumericalCalendarDate $row.decisionDate)
        if(-not $seen.Add("$($row.instrumentId)|$($row.decisionDate)")){throw 'Duplicate instrument/date split row.'}
        $partition=if($row.decisionDate -lt $ValidationFrom){'TRAIN'}elseif($row.decisionDate -lt $TestFrom){'VALIDATION'}else{'TEST'}
        $boundary=if($partition -eq 'TRAIN'){$ValidationFrom}elseif($partition -eq 'VALIDATION'){$TestFrom}else{$null}
        $state='RETAINED_FOR_DIAGNOSTIC_ONLY'
        if($null -eq $row.exitDate){$state='UNKNOWN_LABEL_END'}
        else{
            [void](ConvertTo-NumericalCalendarDate $row.exitDate)
            if($row.exitDate -le $row.decisionDate){throw 'Label end must follow decision.'}
            # Conservative date-level purge: even equality is removed.
            if($boundary -and $row.exitDate -ge $boundary){$state='PURGED_LABEL_OVERLAP'}
        }
        [pscustomobject]@{instrumentId=$row.instrumentId;decisionDate=$row.decisionDate;exitDate=$row.exitDate;partition=$partition;status=$state}
    })
    [pscustomobject]@{
        version='NUMERICAL_SPLIT_PREFLIGHT_V1';status='DIAGNOSTIC_NOT_FROZEN';validationFrom=$ValidationFrom;testFrom=$TestFrom
        boundaryPolicy='LABEL_END_STRICTLY_BEFORE_NEXT_PARTITION_DECISION_DATE';assignments=$assignments
        purgedCount=@($assignments | Where-Object status -eq 'PURGED_LABEL_OVERLAP').Count
        unknownEndCount=@($assignments | Where-Object status -eq 'UNKNOWN_LABEL_END').Count
        independentDecisionDateCount=@($assignments.decisionDate | Select-Object -Unique).Count
        trainingAuthorized=$false
    }
}

function Get-NumericalReadinessBundle($Features,$Price,[string]$FeatureHash,$Calendar) {
    $calendarReview=Get-NumericalFeatureCalendarReview $Features $Calendar
    $p=$Features.snapshot.payload;$e=$Price.result
    if($Price.version -ne 'NUMERICAL_PRICE_COLLECTION_V1' -or $Price.status -notin @('PRICE_POLICY_REVIEW_REQUIRED','PARTIAL_PRICE_POLICY_REVIEW_REQUIRED') -or
       $Price.inputSha256 -ne $FeatureHash -or $FeatureHash -notmatch '^[A-Fa-f0-9]{64}$' -or
       $e.version -ne 'NUMERICAL_PRICE_EVIDENCE_V1' -or $e.status -ne 'PRICE_POLICY_REVIEW_REQUIRED' -or
       $e.datasetRunId -ne $p.datasetRunId -or $e.datasetManifestHash -ne $p.datasetManifestHash -or
       $e.throughDate -ne $p.asOf -or $e.offset -ne $p.offset -or $e.limit -ne $p.limit){throw 'Price evidence/input hash or scope mismatch.'}
    foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($e.$flag -isnot [bool] -or $e.$flag){throw 'Unsafe price evidence flag.'}}
    foreach($field in @('providerCallCount','modelCallCount','ordersCreated')){if(($e.$field -isnot [int] -and $e.$field -isnot [long]) -or $e.$field -ne 0){throw 'Unsafe price evidence counter.'}}
    if($e.partial -isnot [bool] -or @($e.instruments).Count -ne @($p.instruments).Count -or
       ($Price.status -eq 'PARTIAL_PRICE_POLICY_REVIEW_REQUIRED') -ne $e.partial){throw 'Invalid price evidence count/partial state.'}
    $from=($p.instruments.rows.featureFrom | Sort-Object | Select-Object -First 1)
    if($e.fromDate -ne $from){throw 'Price scope does not cover feature union.'}
    $sessions=@(Get-NumericalCalendarSessions $Calendar)
    $fields=@('previousClose','dailyReturnPercent','sma20','sma50','sma200','ema12','ema26','rsi14','atr14','annualizedVolatility20Percent','volumeRatio20','rangePosition252Percent')
    $rows=[Collections.Generic.List[object]]::new();$policy=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt @($p.instruments).Count;$i++){
        $item=$p.instruments[$i];$priceItem=$e.instruments[$i]
        if($item.instrumentId -ne $priceItem.instrumentId -or $item.symbol -ne $priceItem.symbol -or $priceItem.partial -isnot [bool]){throw 'Price instrument identity/partial mismatch.'}
        $policy.Add([pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;status='UNVERIFIED';partial=$priceItem.partial;storedActionCount=@($priceItem.corporateActions).Count;remainingGates=@($priceItem.remainingGates)})
        $byId=@{};foreach($bar in $item.canonicalBars){$byId[[string]$bar.candleId]=$bar}
        foreach($row in $item.rows){
            $issues=[Collections.Generic.List[string]]::new();$late=0;$unknown=0;$maxDate=$null
            $calendarRow=@($calendarReview.rows | Where-Object {$_.instrumentId -eq $item.instrumentId -and $_.decisionDate -eq $row.decisionDate})[0]
            if($calendarRow.calendarStatus -ne 'MATCHES_REVIEWED_CALENDAR'){$issues.Add('FEATURE_WINDOW_INVALID')}
            $names=if($null -ne $row.features){@($row.features.PSObject.Properties.Name)}else{@()}
            if((($names | Sort-Object) -join ',') -cne (($fields | Sort-Object) -join ',')){$issues.Add('FEATURE_ALLOWLIST_MISMATCH')}
            foreach($field in $fields){
                if($null -eq $row.features -or -not $row.features.PSObject.Properties[$field] -or -not(Test-NumericalBundleNumber $row.features.$field)){$issues.Add('INVALID_NUMERIC_FEATURE');break}
            }
            $cutoff=[DateTimeOffset]::ParseExact(($row.decisionDate+'T16:00:00+05:30'),"yyyy-MM-dd'T'HH:mm:sszzz",[Globalization.CultureInfo]::InvariantCulture)
            foreach($id in $row.sourceCandleIds){
                if(-not $byId.ContainsKey([string]$id)){$issues.Add('UNKNOWN_FEATURE_SOURCE_ID');continue}
                $bar=$byId[[string]$id]
                if($null -eq $maxDate -or $bar.date -gt $maxDate){$maxDate=$bar.date}
                if($bar.date -gt $row.decisionDate){$issues.Add('FUTURE_BAR_IN_FEATURES')}
                if($null -eq $bar.receivedAt){$unknown++}
                else{try{if([DateTimeOffset]::Parse($bar.receivedAt,[Globalization.CultureInfo]::InvariantCulture) -gt $cutoff){$late++}}catch{$unknown++}}
            }
            $label=Get-NumericalLabelPreflight $row.decisionDate $sessions $item.canonicalBars
            $rows.Add([pscustomobject]@{
                instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$row.decisionDate;featureMaxDate=$maxDate
                featureInputStatus=$(if($issues.Count){'BLOCKED'}else{'TRAILING_ALLOWLIST_CHECK_PASSED'})
                issues=@($issues.ToArray() | Select-Object -Unique);receivedAfterCutoffCount=$late;unknownReceivedAtCount=$unknown
                asKnownReplayStatus=$(if($late -or $unknown){'NOT_ESTABLISHED'}else{'RECEIPT_TIMES_ONLY_NOT_FULL_VINTAGE_PROOF'})
                labelPreflight=$label
            })
        }
    }
    $splitRows=@(foreach($row in $rows){[pscustomobject]@{instrumentId=$row.instrumentId;decisionDate=$row.decisionDate;exitDate=$row.labelPreflight.exitDate}})
    $split=Get-NumericalSplitPreflight $splitRows $p.decisionDates[1] $p.decisionDates[2]
    [pscustomobject]@{
        version='NUMERICAL_COORDINATED_PREFLIGHT_V1';status='BLOCKED_FOR_TRAINING';datasetRunId=$p.datasetRunId;datasetManifestHash=$p.datasetManifestHash
        calendarReview=$calendarReview;priceEvidencePartial=$e.partial;priceReview=$policy.ToArray();rows=$rows.ToArray();splitPreflight=$split
        summary=[pscustomobject]@{
            candidateRowCount=$rows.Count;featureInputPassedCount=@($rows | Where-Object featureInputStatus -eq 'TRAILING_ALLOWLIST_CHECK_PASSED').Count
            arithmeticOnlyCount=@($rows | Where-Object {$_.labelPreflight.status -eq 'STORED_PRICE_ARITHMETIC_ONLY'}).Count
            unavailableHorizonCount=@($rows | Where-Object {$_.labelPreflight.status -eq 'CALENDAR_HORIZON_UNAVAILABLE'}).Count
            labelInputProblemCount=@($rows | Where-Object {$_.labelPreflight.status -notin @('STORED_PRICE_ARITHMETIC_ONLY','CALENDAR_HORIZON_UNAVAILABLE')}).Count
            pricePolicyVerifiedCount=0;certifiedLabelCount=0;purgedCount=$split.purgedCount;unknownLabelEndCount=$split.unknownEndCount
        }
        remainingGates=@('PRICE_ACTION_COVERAGE_AND_ADJUSTMENT_PROVENANCE','EXECUTABLE_PRICES_AND_COST_POLICY','LABEL_HORIZON_CALENDAR_AND_BARS','MULTI_DATE_DATASET_AND_FROZEN_PURGED_SPLITS','RESEARCH_AVAILABILITY_UNIVERSE_AND_SOURCE_RIGHTS')
        trainingAuthorized=$false;databaseWritesPerformed=$false;providerCallCount=0;modelCallCount=0;ordersCreated=0
        limitations='Offline diagnostic only. Stored-price arithmetic is not certified returns, executable labels or profits. Costs 0/25/50/100 bps are sensitivity scenarios, not broker fees. No actions applied. Three sampled dates cannot constitute independent model evaluation. Split boundaries are diagnostics, not frozen folds; missing end dates are excluded. Feature checks cover allowlist, types and source dates, not full feature recalculation or all leakage. Current universe and retrospective backfill remain disclosed. No fitting, transforms, actual labels or orders.'
    }
}
