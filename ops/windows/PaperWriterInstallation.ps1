# Definitions only. Administrator password is passed only in the child process environment.
function Get-PaperWriterInstallResource([string]$Name) {
    $allowed=@('writer-install-plan-v1.sql','writer-install-guard-v1.sql','writer-install-grants-v1.sql','writer-install-owner-v1.sql','writer-install-verify-v1.sql','approval-writer-v1.sql')
    if($Name -cnotin $allowed){throw 'Unknown installer resource.'}
    return [IO.File]::ReadAllText((Join-Path $PSScriptRoot ('../../marketbrain-service/src/main/resources/paper/'+$Name))).Replace("`r`n","`n").Trim()
}
function Assert-PaperWriterInstallPlan($Envelope) {
    if($Envelope.planHash -cnotmatch '^[a-f0-9]{32}$' -or $Envelope.plan.version -cne 'PAPER_WRITER_INSTALL_PLAN_V1'){throw 'Invalid installation plan.'}
    $p=$Envelope.plan
    if($p.database -cnotmatch '^[a-z][a-z0-9_]{0,62}$' -or $p.databaseOid -cnotmatch '^[0-9]+$' -or $p.clusterId -cnotmatch '^[0-9]+$'){throw 'Invalid target identity.'}
    if($p.adminSuperuser -isnot [bool] -or -not $p.adminSuperuser){
        $failure=[InvalidOperationException]::new('A PostgreSQL superuser is required; do not elevate the application role.')
        $failure.Data['PaperWriterCode']='POSTGRESQL_ADMIN_REQUIRED';throw $failure
    }
    if($p.schemaExists -isnot [bool] -or -not $p.schemaExists){throw 'Public schema required.'}
    foreach($field in @('serverVersion','roleCount','membershipCount','relationCount','requiredTables','roleCollisions','functionCollisions','publicCreateSchemas','publicDefiners','defaultFunctionAcls')) {
        if(($p.$field -isnot [int] -and $p.$field -isnot [long]) -or $p.$field -lt 0){throw 'Invalid catalog count.'}
    }
    if($p.serverVersion -lt 180000 -or $p.serverVersion -ge 190000 -or $p.roleCount -lt 1 -or $p.roleCount -gt 128 -or $p.membershipCount -gt 256 -or $p.relationCount -gt 512 -or $p.requiredTables -ne 12){throw 'Unsupported catalog scope.'}
    foreach($field in @('roleCollisions','functionCollisions','publicCreateSchemas','publicDefiners','defaultFunctionAcls')){if($p.$field -ne 0){throw "Installation blocked: $field"}}
    if($p.publicDatabaseCreate -isnot [bool] -or $p.publicDatabaseCreate -or $p.publicTemp -isnot [bool]){throw 'Unreviewed PUBLIC permission.'}
    if(@($p.roles).Count -ne $p.roleCount -or @($p.memberships).Count -ne $p.membershipCount){throw 'Truncated inventory.'}
    if(@($p.roles|Select-Object -ExpandProperty roleOid -Unique).Count -ne $p.roleCount -or @($p.roles|Select-Object -ExpandProperty roleName -Unique).Count -ne $p.roleCount){throw 'Duplicate role inventory.'}
    foreach($r in $p.roles){
        if(-not $r.roleName -or $r.roleName -match '[\x00-\x1F\x7F]' -or $r.roleName.Length -gt 63){throw 'Role display name needs manual review.'}
        foreach($field in @('login','superuser','createRole','createDatabase','inherit','replication','bypassRls','temp','explicitTemp')){if($r.$field -isnot [bool]){throw 'Invalid role flags.'}}
    }
}
function ConvertTo-PaperSqlLiteral([string]$Value) {
    if($Value.Contains([char]0)){throw 'NUL not permitted.'};return "'"+$Value.Replace("'","''")+"'"
}
function Get-PaperBodyMd5([string]$Body) {
    $hash=[Security.Cryptography.MD5]::Create()
    try{return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function New-PaperWriterInstallSql([ValidateSet('Plan','Rehearse','Apply','Verify')][string]$Mode,$Envelope) {
    $plan=Get-PaperWriterInstallResource 'writer-install-plan-v1.sql'
    $start="-- MB_INSTALL_SECTION: session`nBEGIN; SET LOCAL statement_timeout='15s'; SET LOCAL lock_timeout='3s'; SET LOCAL idle_in_transaction_session_timeout='20s'; SET LOCAL search_path=pg_catalog; SET LOCAL standard_conforming_strings=on;`n"
    if($Mode -ceq 'Plan'){return $start+"SET TRANSACTION READ ONLY; WITH p AS ($plan) SELECT jsonb_build_object('plan',plan,'planHash',md5(plan::text)) FROM p; ROLLBACK;"}
    Assert-PaperWriterInstallPlan $Envelope
    # Fixed trusted identifier, not caller-controlled SQL; canonical unquoted GUC representation.
    $candidate=(Get-PaperWriterInstallResource 'approval-writer-v1.sql').Replace('__SCHEMA__','public')
    $bodies=[regex]::Matches($candidate,'(?s)AS \$\$(.*?)\$\$;')
    if($bodies.Count -ne 2){throw 'Candidate function boundaries changed.'}
    $literal=(ConvertTo-PaperSqlLiteral ($Envelope.plan|ConvertTo-Json -Depth 12 -Compress))+'::jsonb'
    if($literal.Contains('$mb$')){throw 'Catalog contains a reserved block delimiter; manual review required.'}
    $verify=(Get-PaperWriterInstallResource 'writer-install-verify-v1.sql').Replace('__APPROVED_PLAN__',$literal).Replace('__PLAN_HASH__',$Envelope.planHash).Replace('__LOCK_HASH__',(Get-PaperBodyMd5 $bodies[0].Groups[1].Value)).Replace('__RECORD_HASH__',(Get-PaperBodyMd5 $bodies[1].Groups[1].Value))
    $receipt="SELECT jsonb_build_object('version','PAPER_WRITER_INSTALL_CHECK_V1','phase','$Mode','checksPassed',true,'planHash','$($Envelope.planHash)','loginEnabled',false,'applicationWriterActivated',false,'actionExecutionEnabled',false,'accountRowsWritten',false,'databaseAcl',(SELECT coalesce(datacl::text,'') FROM pg_catalog.pg_database WHERE datname=current_database()));`n"
    if($Mode -ceq 'Verify'){return $start+"SET TRANSACTION READ ONLY;`n-- MB_INSTALL_SECTION: verification`n"+$verify+"`n"+$receipt+'ROLLBACK;'}
    $guard=(Get-PaperWriterInstallResource 'writer-install-guard-v1.sql').Replace('__PLAN_QUERY__',$plan).Replace('__PLAN_HASH__',$Envelope.planHash)
    $grants=(Get-PaperWriterInstallResource 'writer-install-grants-v1.sql').Replace('__PLAN_HASH__',$Envelope.planHash)
    $owner=Get-PaperWriterInstallResource 'writer-install-owner-v1.sql'
    $end=if($Mode -ceq 'Apply'){'COMMIT;'}else{'ROLLBACK;'}
    # Receipt emitted before transaction end is not success without native exit zero and independent readback.
    return $start+"-- MB_INSTALL_SECTION: guard`n"+$guard+"`n-- MB_INSTALL_SECTION: grants`n"+$grants+"`n-- MB_INSTALL_SECTION: functions`n"+$candidate+"`n-- MB_INSTALL_SECTION: ownership`n"+$owner+"`n-- MB_INSTALL_SECTION: verification`n"+$verify+"`n-- MB_INSTALL_SECTION: receipt`n"+$receipt+$end
}
function Get-PaperInstallerDiagnostic([string]$Stderr,[string]$Sql) {
    # Report only codes, bounded numeric locations and fixed section names. Never raw error text/SQL.
    $states=@([regex]::Matches($Stderr,'(?:ERROR|FATAL):\s+([A-Z0-9]{5})(?=[:\s]|$)')|ForEach-Object {$_.Groups[1].Value}|Select-Object -Unique|Select-Object -First 8)
    $lines=$Sql -split "`n"
    $locations=@([regex]::Matches($Stderr,'(?m)^psql:(?:<stdin>|-):([0-9]{1,7}):')|ForEach-Object {[int]$_.Groups[1].Value}|Where-Object {$_ -gt 0 -and $_ -le $lines.Count}|Select-Object -Unique|Select-Object -First 8)
    $bodyLines=@([regex]::Matches($Stderr,'(?m)^CONTEXT:\s+compilation of PL/pgSQL function "inline_code_block" near line ([0-9]{1,7})\s*$')|ForEach-Object {[int]$_.Groups[1].Value}|Where-Object {$_ -gt 0 -and $_ -le $lines.Count}|Select-Object -Unique|Select-Object -First 8)
    $sections=@(foreach($location in $locations){
        $section='unknown'
        for($i=0;$i -lt $location;$i++){if($lines[$i] -cmatch '^-- MB_INSTALL_SECTION: (session|guard|grants|functions|ownership|verification|receipt)$'){$section=$Matches[1]}}
        [pscustomobject]@{inputLine=$location;section=$section}
    })
    $tags=@([regex]::Matches($Sql,"RAISE EXCEPTION '([A-Za-z0-9 /-]+)'")|ForEach-Object {$_.Groups[1].Value}|Select-Object -Unique|Where-Object {$Stderr.Contains($_)}|Select-Object -First 8)
    return [pscustomobject]@{sqlStates=$states;inputLocations=$sections;inlineBlockLines=$bodyLines;assertionFailures=$tags}
}
function Assert-PaperWriterInstallReceipt($Receipt,[string]$Phase,[string]$Hash) {
    if($Receipt.version -cne 'PAPER_WRITER_INSTALL_CHECK_V1' -or $Receipt.phase -cne $Phase -or $Receipt.planHash -cne $Hash -or
       $Receipt.checksPassed -isnot [bool] -or -not $Receipt.checksPassed){throw 'Installation checks not proven.'}
    foreach($field in @('loginEnabled','applicationWriterActivated','actionExecutionEnabled','accountRowsWritten')){if($Receipt.$field -isnot [bool] -or $Receipt.$field){throw 'Unsafe installation receipt.'}}
}
function Invoke-PaperInstallerPsql([string]$Executable,[string]$Database,[int]$Port,[string]$Admin,[string]$Password,[string]$Sql) {
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$Executable;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $p.StartInfo.StandardInputEncoding=[Text.UTF8Encoding]::new($false)
    $p.StartInfo.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $p.StartInfo.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    foreach($key in @($p.StartInfo.Environment.Keys)){if($key -like 'PG*'){[void]$p.StartInfo.Environment.Remove($key)}}
    $p.StartInfo.Environment['PGPASSWORD']=$Password
    $p.StartInfo.Environment['PGCONNECT_TIMEOUT']='5'
    $p.StartInfo.Environment['PGCLIENTENCODING']='UTF8'
    $p.StartInfo.Environment['PGOPTIONS']='-c statement_timeout=15000 -c lock_timeout=3000 -c idle_in_transaction_session_timeout=20000'
    foreach($arg in @('--no-psqlrc','--no-password','--host','127.0.0.1','--port',[string]$Port,'--dbname',$Database,'--username',$Admin,'--quiet','--tuples-only','--no-align','--set','ON_ERROR_STOP=1','--set','VERBOSITY=verbose','--file','-')){[void]$p.StartInfo.ArgumentList.Add($arg)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$last=0;$done=$false
    try {
        [void]$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        $write=$p.StandardInput.WriteAsync($Sql)
        if(-not $write.Wait(10000)){throw 'SQL input deadline exceeded.'};$p.StandardInput.Close()
        while($watch.Elapsed.TotalSeconds -lt 120){if($p.WaitForExit(250)){$done=$true;break};if($watch.Elapsed.TotalSeconds-$last -ge 10){$last=$watch.Elapsed.TotalSeconds;Write-Host ('Database stage running: {0:N0}s / 120s limit' -f $last)}}
        if(-not $done){$p.Kill($true);[void]$p.WaitForExit(5000)}
        if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Output deadline exceeded.'}
        $diagnostic=Get-PaperInstallerDiagnostic $err.Result $Sql
        return [pscustomobject]@{exitCode=if($done){$p.ExitCode}else{-999};timedOut=(-not $done);elapsedSeconds=$watch.Elapsed.TotalSeconds;stdout=$out.Result;stderrCharacters=$err.Result.Length;sqlStates=$diagnostic.sqlStates;assertionFailures=$diagnostic.assertionFailures;inputLocations=$diagnostic.inputLocations;inlineBlockLines=$diagnostic.inlineBlockLines}
    } finally {try{if(-not $p.HasExited){$p.Kill($true)}}catch{};[void]$p.StartInfo.Environment.Remove('PGPASSWORD');$p.Dispose()}
}
