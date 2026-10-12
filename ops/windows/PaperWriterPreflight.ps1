# Definitions only; no database, application or Docker activity on import.
function Assert-PaperWriterCatalog($Result,[string]$Schema) {
    if($Result.version -cne 'PAPER_WRITER_PREFLIGHT_V1' -or $Result.status -cne 'CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED' -or
       $Result.scope -cne 'CONFIGURED_DATABASE_CATALOG_ONLY_NOT_RUNTIME_IDENTITY_OR_INSTALLATION_PROOF'){throw 'Wrong catalog report contract.'}
    foreach($field in @('applicationDatabaseWritesPerformed','applicationWriterActivated','actionExecutionEnabled')) {
        if($Result.$field -isnot [bool] -or $Result.$field){throw "Unsafe catalog flag: $field"}
    }
    foreach($field in @('readOnly','repeatableRead','unchangedSessionIdentity')) {
        if($Result.session.$field -isnot [bool] -or -not $Result.session.$field){throw 'Read-only session guard missing.'}
    }
    foreach($field in @('providerCalls','telegramCalls','modelCalls')) {
        if(($Result.$field -isnot [int] -and $Result.$field -isnot [long]) -or $Result.$field -ne 0){throw 'External call counter invalid.'}
    }
    if($Result.connectionAttempted -isnot [bool] -or -not $Result.connectionAttempted -or $Result.schema.schemaName -cne $Schema){throw 'Target schema/connection mismatch.'}
    $names=@('paper_approval_proposal','paper_approval_token','telegram_binding','paper_portfolio','paper_ledger_account','paper_ledger_command','paper_ledger_position','instrument','paper_approval_delivery','paper_approval_key_binding','paper_ledger_order','paper_ledger_fill')
    if(@($Result.tables).Count -ne $names.Count){throw 'Incomplete catalog table coverage.'}
    foreach($name in $names) {
        $rows=@($Result.tables|Where-Object tableName -CEQ $name)
        if($rows.Count -ne 1 -or $rows[0].present -isnot [bool]){throw 'Missing or duplicate catalog table.'}
        if($rows[0].present){foreach($key in @('rowSecurity','forceRowSecurity','currentRoleOwnerMembership','currentRoleSelect','publicSelect','publicWrite')){if($rows[0].$key -isnot [bool]){throw 'Incomplete table privilege evidence.'}}}
    }
    foreach($field in @('proposedRoleCollisions','writerFunctionCollisions','publicCreateSchemas','publicCallableDefiners','installationBlockers')) {
        if($null -eq $Result.PSObject.Properties[$field] -or $null -eq $Result.$field){throw 'Missing catalog list.'}
    }
    if(@($Result.proposedRoleCollisions).Count -gt 2){throw 'Unexpected role list.'}
    foreach($field in @('writerFunctionCollisions','publicCreateSchemas','publicCallableDefiners')) {if(@($Result.$field).Count -gt 21){throw 'Catalog limit exceeded.'}}
    $bounded=(@($Result.writerFunctionCollisions).Count -eq 21 -or @($Result.publicCreateSchemas).Count -eq 21 -or @($Result.publicCallableDefiners).Count -eq 21)
    if($Result.catalogListBoundReached -isnot [bool] -or $Result.catalogListBoundReached -ne $bounded){throw 'Catalog truncation flag mismatch.'}
    if($Result.elapsedSeconds -is [bool] -or $Result.elapsedSeconds -is [string] -or $null -eq $Result.elapsedSeconds -or
       [double]::IsNaN([double]$Result.elapsedSeconds) -or [double]::IsInfinity([double]$Result.elapsedSeconds) -or $Result.elapsedSeconds -lt 0){throw 'Invalid catalog timing.'}
}

function Invoke-PaperCatalogProcess([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[int]$LimitSeconds) {
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$Executable;$p.StartInfo.WorkingDirectory=$WorkingDirectory
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    foreach($a in $Arguments){[void]$p.StartInfo.ArgumentList.Add($a)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$heartbeat=0;$done=$false
    try {
        [void]$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        while($watch.Elapsed.TotalSeconds -lt $LimitSeconds) {
            if($p.WaitForExit(250)){$done=$true;break}
            if($watch.Elapsed.TotalSeconds-$heartbeat -ge 10){$heartbeat=$watch.Elapsed.TotalSeconds;Write-Host ('  Stage running: {0:N0}s / {1}s limit' -f $heartbeat,$LimitSeconds)}
        }
        if(-not $done){$p.Kill($true);[void]$p.WaitForExit(5000)}
        if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Process output deadline exceeded.'}
        return [pscustomobject]@{exitCode=if($done){$p.ExitCode}else{-999};timedOut=(-not $done);elapsedSeconds=$watch.Elapsed.TotalSeconds;stdout=$out.Result;stderr=$err.Result}
    } finally {try{if(-not $p.HasExited){$p.Kill($true)}}catch{};$p.Dispose()}
}
