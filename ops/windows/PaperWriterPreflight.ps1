# Definitions only; no database, application or Docker activity on import.
function Get-PaperCatalogRuntimeEnvironment($Container,[string]$Repository) {
    if($Container.Id -cnotmatch '^[a-f0-9]{64}$' -or $Container.State.Running -isnot [bool] -or -not $Container.State.Running -or -not $Container.State.StartedAt){throw 'RUNTIME_CONTAINER_NOT_RUNNING'}
    $labels=$Container.Config.Labels
    if($labels.'com.docker.compose.service' -cne 'marketbrain-service' -or
       [string]::IsNullOrWhiteSpace($labels.'com.docker.compose.project.working_dir') -or
       [IO.Path]::GetFullPath($labels.'com.docker.compose.project.working_dir').TrimEnd('\','/') -ine [IO.Path]::GetFullPath($Repository).TrimEnd('\','/')){throw 'RUNTIME_WORKSPACE_MISMATCH'}
    $values=@{}
    foreach($entry in $Container.Config.Env) {
        $pair=([string]$entry).Split('=',2)
        if($pair.Count -ne 2 -or $values.ContainsKey($pair[0])){throw 'RUNTIME_ENVIRONMENT_AMBIGUOUS'}
        $values[$pair[0]]=$pair[1]
    }
    # Refuse alternate Spring overrides rather than claiming these three variables are authoritative.
    if(@($values.Keys|Where-Object {$_ -match '^(SPRING_|JAVA_TOOL_OPTIONS$|JDK_JAVA_OPTIONS$|_JAVA_OPTIONS$)'}).Count){throw 'RUNTIME_ALTERNATE_CONFIGURATION_REQUIRES_REVIEW'}
    if($values.MARKETBRAIN_EXECUTION_MODE -cne 'PAPER'){throw 'RUNTIME_PAPER_MODE_REQUIRED'}
    $selected=@{}
    foreach($key in @('MARKETBRAIN_DB_URL','MARKETBRAIN_DB_USERNAME','MARKETBRAIN_DB_PASSWORD')) {
        if([string]::IsNullOrWhiteSpace($values[$key])){throw 'RUNTIME_DATABASE_CONFIGURATION_MISSING'}
        $selected[$key]=$values[$key]
    }
    if($selected.MARKETBRAIN_DB_URL -notmatch '^jdbc:postgresql://'){throw 'RUNTIME_DATABASE_URL_UNSUPPORTED'}
    return $selected
}

function Assert-PaperWriterCatalog($Result,[string]$Schema,[switch]$Publisher) {
    $expectedVersion=if($Publisher){'PAPER_PUBLISHER_PREFLIGHT_V1'}else{'PAPER_WRITER_PREFLIGHT_V1'}
    if($Publisher -and ($Result.publisherActivated -isnot [bool] -or $Result.publisherActivated -or $Result.target.database -cnotmatch '^[a-z][a-z0-9_]{0,62}$' -or $Result.target.databaseOid -is [string] -or $Result.target.databaseOid -is [bool] -or $Result.target.databaseOid -le 0)){throw 'Invalid publisher target or activation evidence.'}
    if($Result.version -cne $expectedVersion -or $Result.status -cne 'CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED' -or
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

function Invoke-PaperCatalogProcess([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[int]$LimitSeconds,[string]$InputText) {
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$Executable;$p.StartInfo.WorkingDirectory=$WorkingDirectory
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    if($InputText){$p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.StandardInputEncoding=[Text.UTF8Encoding]::new($false)}
    foreach($a in $Arguments){[void]$p.StartInfo.ArgumentList.Add($a)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$heartbeat=0;$done=$false
    try {
        [void]$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        if($InputText){$write=$p.StandardInput.WriteAsync($InputText);if(-not $write.Wait(10000)){throw 'Process input deadline exceeded.'};$p.StandardInput.Close()}
        while($watch.Elapsed.TotalSeconds -lt $LimitSeconds) {
            if($p.WaitForExit(250)){$done=$true;break}
            if($watch.Elapsed.TotalSeconds-$heartbeat -ge 10){$heartbeat=$watch.Elapsed.TotalSeconds;Write-Host ('  Stage running: {0:N0}s / {1}s limit' -f $heartbeat,$LimitSeconds)}
        }
        if(-not $done){$p.Kill($true);[void]$p.WaitForExit(5000)}
        if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Process output deadline exceeded.'}
        return [pscustomobject]@{exitCode=if($done){$p.ExitCode}else{-999};timedOut=(-not $done);elapsedSeconds=$watch.Elapsed.TotalSeconds;stdout=$out.Result;stderr=$err.Result}
    } finally {try{if(-not $p.HasExited){$p.Kill($true)}}catch{};$p.Dispose()}
}
