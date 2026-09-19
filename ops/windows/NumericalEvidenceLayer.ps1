# Definitions only: bounded saved-file inspection and independent synthetic evidence review.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1')

function Get-EvidenceBytesHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-RetrospectiveSnapshotAssessment([string]$Path) {
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($item.PSIsContainer -or $item.Length -gt 8MB){throw 'Saved mapping must be a file bounded to 8 MiB.'}
    $bytes=[IO.File]::ReadAllBytes($item.FullName)
    $hash=Get-EvidenceBytesHash $bytes
    if($hash -cne '610a71cb2932688abf29d45f99d7e5dd86f1807b692303e63b234359d4449d08'){throw 'Not the accepted E65 mapping snapshot. Preserve it; do not rerun collection.'}
    $saved=[Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    $r=$saved.result
    if($saved.sourceSha256 -ine 'E983F6EE5B0B6DDA2DE40DC27D37451B2DD58C5D360CBBE092672B9EFD419CA8' -or
       $r.version -cne 'NUMERICAL_RESEARCH_MAPPING_V1' -or $r.status -cne 'MAPPED_RESEARCH_TRAINING_BLOCKED'){throw 'Saved source binding/status mismatch.'}
    foreach($key in @('trainingAuthorized','databaseWritesPerformed')){if($r.$key -isnot [bool] -or $r.$key){throw "Unsafe mapping flag: $key"}}
    foreach($key in @('trainingEligibleCount','certifiedLabelCount','databaseQueryCount','providerCallCount','modelCallCount','ordersCreated')){Assert-BaselineNumber $r.$key 0 $key}
    Assert-BaselineNumber $r.rowCount 600 'rowCount';Assert-BaselineNumber $r.mappingReadyCount 600 'mappingReadyCount'
    if(@($r.rows).Count -ne 600 -or @($r.dateCoverage).Count -ne 150 -or @($r.featureNames).Count -ne 10){throw 'Saved cohort dimensions mismatch.'}
    $identities=@{};$dates=@{};$symbols=@{};$lateRows=0
    foreach($row in $r.rows){
        $key='{0}@{1}' -f $row.instrumentId,$row.decisionDate
        if($identities.ContainsKey($key)){throw 'Duplicate saved identity.'};$identities[$key]=$true
        if(-not $dates.ContainsKey($row.decisionDate)){$dates[$row.decisionDate]=0};$dates[$row.decisionDate]++
        $symbols[$row.symbol]=$true
        if($row.trainingEligible -isnot [bool] -or $row.trainingEligible -or $row.mappingReady -isnot [bool] -or -not $row.mappingReady){throw 'Saved row eligibility changed.'}
        if(@($row.features.PSObject.Properties).Count -ne 10){throw 'Saved feature count mismatch.'}
        foreach($name in $r.featureNames){Assert-BaselineNumber $row.features.$name ([double]$row.features.$name) "feature $name"}
        if($row.receivedAfterCutoffCount -gt 0){$lateRows++}
    }
    if((($symbols.Keys | Sort-Object) -join ',') -cne 'LEMONTREE,MARUTI,NATIONALUM,TARIL'){throw 'Saved symbols mismatch.'}
    if($dates.Count -ne 150 -or @($dates.Values | Where-Object {$_ -ne 4}).Count -gt 0 -or $lateRows -ne 600){throw 'Saved date/receipt evidence mismatch.'}
    [pscustomobject]@{status='SAVED_SNAPSHOT_ASSESSED_NOT_FIT_RELEASED';sourceFile=$item.Name;sourceSha256=$hash
        sourceUnchanged=((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ieq $hash)
        rowCount=600;dateCount=150;featureCount=10;symbols=@($symbols.Keys | Sort-Object);lateReceiptRows=$lateRows
        pointInTimeTrainingEligibleRows=0;retrospectiveTrainingEligibleRows=$null;marketFitAuthorized=$false
        sourceRecollectionPerformed=$false;featuresRecomputed=$false;existingBlockerCounts=$r.blockerCounts
        limitations=@('Snapshot integrity is not original publication-time evidence.','Retrospective fitting eligibility remains unassessed.',
            'Source price/corporate-action evidence, rights, final evaluation criteria and scoped fit approval remain open.')}
}
function Read-EvidenceInt([byte[]]$Bytes,[ref]$Offset) {
    if($Offset.Value+4 -gt $Bytes.Length){throw 'Truncated integer.'}
    $n=[int64]$Bytes[$Offset.Value]*16777216+[int64]$Bytes[$Offset.Value+1]*65536+[int64]$Bytes[$Offset.Value+2]*256+$Bytes[$Offset.Value+3]
    $Offset.Value+=4;if($n -gt [int]::MaxValue){throw 'Oversized integer.'};return [int]$n
}
function Read-EvidenceAscii([byte[]]$Bytes,[ref]$Offset) {
    if($Offset.Value+2 -gt $Bytes.Length){throw 'Truncated string.'}
    $n=[int]$Bytes[$Offset.Value]*256+$Bytes[$Offset.Value+1];$Offset.Value+=2
    if($n -le 0 -or $Offset.Value+$n -gt $Bytes.Length){throw 'Invalid string length.'}
    $part=[byte[]]$Bytes[$Offset.Value..($Offset.Value+$n-1)];$Offset.Value+=$n
    if(@($part | Where-Object {$_ -gt 127}).Count){throw 'Fixture metadata must be ASCII.'}
    return [Text.Encoding]::ASCII.GetString($part)
}
function Assert-EvidenceLayerResult($Result) {
    if($Result.version -cne 'NUMERICAL_EVIDENCE_LEDGER_V1' -or $Result.status -cne 'EVIDENCE_CHECKS_PASSED' -or $Result.syntheticOnly -isnot [bool] -or -not $Result.syntheticOnly){throw 'Wrong synthetic evidence result.'}
    foreach($key in @('marketDataCollectionEnabled','marketFitAuthorized','databaseWritesPerformed','actionExecutionEnabled')){if($Result.$key -isnot [bool] -or $Result.$key){throw "Unsafe flag: $key"}}
    foreach($key in @('ordersCreated','providerCallCount','llmCallCount','signalsCreated','failedCheckCount')){Assert-BaselineNumber $Result.$key 0 $key}
    $names=@('append_and_restart','duplicate_no_write','conflict_quarantined','correction_preserves_original','unknown_correction_rejected',
        'unknown_availability_quarantined','future_input_quarantined','stale_input_quarantined','clock_quarantined','rights_and_price_not_inferred',
        'missing_features_retained','outcome_feature_rejected','non_finite_rejected','concurrent_writer_fails_fast','policy_mismatch_rejected',
        'record_limit_no_write','byte_limit_no_write','corruption_blocks_append_and_recovery','partial_tail_new_branch_original_preserved',
        'recovery_destination_not_overwritten','incomplete_header_not_auto_repaired','future_outcomes_and_permissions_not_created')
    if($Result.checkCount -ne 22 -or @($Result.checks).Count -ne 22){throw 'Incomplete evidence suite.'}
    $seen=@{}
    foreach($check in $Result.checks){
        if($names -cnotcontains $check.name -or $seen.ContainsKey($check.name) -or $check.passed -isnot [bool] -or -not $check.passed -or $check.failure){throw 'Failed/missing/duplicate evidence check.'}
        $seen[$check.name]=$true;Assert-BaselineNumber $check.elapsedMillis ([double]$check.elapsedMillis) 'check timing'
        if($check.elapsedMillis -lt 0){throw 'Negative timing.'}
    }
    $bytes=[Convert]::FromBase64String($Result.ledgerBase64)
    if($bytes.Length -gt 128KB -or (Get-EvidenceBytesHash $bytes) -cne $Result.audit.fileHash -or
       $Result.audit.status -cne 'COMPLETE' -or $Result.audit.totalBytes -ne $bytes.Length -or $Result.audit.validPrefixBytes -ne $bytes.Length){throw 'Embedded ledger integrity mismatch.'}
    $offset=0;if((Read-EvidenceInt $bytes ([ref]$offset)) -ne 0x4d424531 -or (Read-EvidenceAscii $bytes ([ref]$offset)) -cne $Result.version){throw 'Ledger header mismatch.'}
    $policyHash=Read-EvidenceAscii $bytes ([ref]$offset);$schemaHash=Read-EvidenceAscii $bytes ([ref]$offset)
    # Exact fixture policy, never production defaults. Java canonical JSON is sorted.
    if($policyHash -cne (Get-TenFeatureTextHash '{"maxClockSkewMillis":1000,"maxFeatureAgeSeconds":60,"maxRecords":30,"maxStoreBytes":131072}')){throw 'Fixture policy binding mismatch.'}
    Assert-BaselineNumber $Result.fixturePolicyNotRuntimeDefaults.maxClockSkewMillis 1000 'fixture skew'
    Assert-BaselineNumber $Result.fixturePolicyNotRuntimeDefaults.maxFeatureAgeSeconds 60 'fixture age'
    Assert-BaselineNumber $Result.fixturePolicyNotRuntimeDefaults.maxRecords 30 'fixture record cap'
    Assert-BaselineNumber $Result.fixturePolicyNotRuntimeDefaults.maxStoreBytes 131072 'fixture byte cap'
    $features=@('dailyReturnPercent','closeToSma20Percent','closeToSma50Percent','closeToSma200Percent','ema12ToEma26Percent','rsi14','atr14ToClosePercent','annualizedVolatility20Percent','volumeRatio20','rangePosition252Percent')
    $units=@('PERCENT','PERCENT','PERCENT','PERCENT','PERCENT','INDEX_0_100','PERCENT','PERCENT','RATIO','PERCENT_0_100')
    $schemaText='[['+('"'+($features -join '","')+'"')+'],['+('"'+($units -join '","')+'"')+']]'
    if($schemaHash -cne (Get-TenFeatureTextHash $schemaText) -or $offset -ne $Result.headerBytes -or
       ($Result.featureOrder -join ',') -cne ($features -join ',') -or ($Result.featureUnits -join ',') -cne ($units -join ',')){throw 'Feature schema binding mismatch.'}
    $kinds=@('ORIGINAL_RECORDED','QUARANTINED_CONFLICT','CORRECTION_RECORDED_REVIEW_REQUIRED','ORIGINAL_RECORDED')
    if(@($Result.audit.entries).Count -ne 4){throw 'Missing fixture records.'}
    $previous='0'*64;$i=0;$firstFrameEnd=0
    while($offset -lt $bytes.Length){
        if($i -ge 4){throw 'Unexpected ledger frame.'};$n=Read-EvidenceInt $bytes ([ref]$offset)
        if($n -le 0 -or $n -gt 32768 -or $offset+$n+32 -gt $bytes.Length){throw 'Invalid frame length.'}
        $payload=[byte[]]$bytes[$offset..($offset+$n-1)];$offset+=$n
        $digest=([BitConverter]::ToString($bytes,$offset,32)).Replace('-','').ToLowerInvariant();$offset+=32
        if((Get-EvidenceBytesHash $payload) -cne $digest){throw 'Frame checksum mismatch.'}
        $e=$Result.audit.entries[$i];$p=0;$sequence=Read-EvidenceInt $payload ([ref]$p)
        $prior=Read-EvidenceAscii $payload ([ref]$p);$kind=Read-EvidenceAscii $payload ([ref]$p);$size=Read-EvidenceInt $payload ([ref]$p)
        if($size -le 0 -or $p+$size -ne $payload.Length){throw 'Snapshot length mismatch.'}
        $id=Get-EvidenceBytesHash ([byte[]]$payload[$p..($p+$size-1)])
        if($sequence -ne $i+1 -or $e.sequence -ne $sequence -or $prior -cne $previous -or $e.previousHash -cne $previous -or
           $e.entryHash -cne $digest -or $kind -cne $kinds[$i] -or $e.disposition -cne $kind -or $e.snapshotId -cne $id){throw 'Entry identity/chain/disposition mismatch.'}
        foreach($flag in @('trainingEligible','collectionAuthorized')){if($e.assessment.$flag -isnot [bool] -or $e.assessment.$flag){throw 'Entry authorization changed.'}}
        $previous=$digest;$i++;if($i -eq 1){$firstFrameEnd=$offset}
    }
    if($i -ne 4 -or $Result.audit.entries[2].snapshot.supersedesId -cne $Result.audit.entries[0].snapshotId -or
       $Result.audit.entries[3].assessment.reasons -cnotcontains 'FEATURES_INCOMPLETE'){throw 'Correction/quarantine evidence missing.'}
    if($Result.recovery.status -cne 'RECOVERED_TO_NEW_STORE_ORIGINAL_PRESERVED' -or $Result.recovery.recoveredEntries -ne 1 -or
       $Result.recovery.preservedSourceBytes -ne $Result.recovery.recoveredPrefixBytes+2 -or
       $Result.recovery.sourceFileHash -ceq $Result.recovery.recoveredFileHash){throw 'Partial-write recovery evidence mismatch.'}
    $first=[byte[]]$bytes[0..($firstFrameEnd-1)];$partial=[byte[]]($first+@([byte]0,[byte]0))
    if($Result.recovery.recoveredPrefixBytes -ne $first.Length -or (Get-EvidenceBytesHash $first) -cne $Result.recovery.recoveredFileHash -or
       (Get-EvidenceBytesHash $partial) -cne $Result.recovery.sourceFileHash){throw 'Recovery hashes do not match fixture bytes.'}
}
