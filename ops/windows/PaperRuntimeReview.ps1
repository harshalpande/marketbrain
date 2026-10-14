# Definitions only. No Docker, credentials, database or messages on import.
function Invoke-PaperRuntimeProcess([string]$Executable,[string[]]$Arguments,[string]$Directory,[int]$LimitSeconds,[byte[]]$InputBytes=$null) {
    if($LimitSeconds -lt 1 -or $LimitSeconds -gt 1800){throw 'RUNTIME_INVALID_DEADLINE'}
    if($null -ne $InputBytes -and $InputBytes.Length -ne 64){throw 'RUNTIME_INVALID_INPUT'}
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$Executable;$p.StartInfo.WorkingDirectory=$Directory
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true;$p.StartInfo.RedirectStandardInput=$true
    foreach($argument in $Arguments){[void]$p.StartInfo.ArgumentList.Add($argument)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$started=$false;$last=0
    try {
        $started=$p.Start();if(-not $started){throw 'RUNTIME_START_FAILED'}
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if($null -ne $InputBytes){$write=$p.StandardInput.BaseStream.WriteAsync($InputBytes,0,$InputBytes.Length);if(-not $write.Wait(5000)){throw 'RUNTIME_STDIN_TIMEOUT'}}
        $p.StandardInput.Close()
        while(-not $p.WaitForExit(250)){
            if($watch.Elapsed.TotalSeconds -ge $LimitSeconds){throw 'RUNTIME_PROCESS_TIMEOUT'}
            if($watch.Elapsed.TotalSeconds-$last -ge 10){$last=$watch.Elapsed.TotalSeconds;Write-Host ('Stage running: {0:N0}s / {1}s deadline' -f $last,$LimitSeconds)}
        }
        if(-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)){throw 'RUNTIME_OUTPUT_TIMEOUT'}
        return @{exitCode=$p.ExitCode;stdout=$stdout.Result;stderr=$stderr.Result;elapsedSeconds=$watch.Elapsed.TotalSeconds}
    } finally {
        if($started -and -not $p.HasExited){try{$p.Kill($true);[void]$p.WaitForExit(5000)}catch{}}
        $p.Dispose()
    }
}
function Assert-PaperRuntimeFixture($Value,[string]$RunId) {
    if($Value.version -cne 'PAPER_RUNTIME_FIXTURE_V1' -or $Value.runId -cne $RunId -or $Value.bootId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or $Value.status -cne 'RUNTIME_FIXTURE_READY_LOCKED'){throw 'RUNTIME_FIXTURE_IDENTITY'}
    foreach($flag in @('applicationDatabaseAccessed','realCredentialUsed','realTelegramVerified','actionExecutionEnabled')){
        if($Value.$flag -isnot [bool] -or $Value.$flag){throw 'RUNTIME_FIXTURE_UNSAFE'}
    }
    $names=@('spring_memory_mode_starts_locked_without_database','approved_100_second_policy_registered','no_publisher_or_execution_bean','locked_callback_never_dials','unix_socket_has_private_permissions','status_starts_locked','stdin_frame_unlocks_process_secret','identical_unlock_replay_is_safe','different_secret_cannot_overwrite','malformed_secret_refused','only_socket_metadata_on_filesystem','explicit_lock_removes_ready_secret','unlock_after_lock_allowed','shutdown_removes_owned_socket','fresh_spring_context_requires_new_unlock','stale_socket_path_never_overwritten','broad_directory_permissions_refused','no_database_attempts_across_suite')
    if(($Value.checkCount -isnot [int] -and $Value.checkCount -isnot [long]) -or $Value.checkCount -ne $names.Count -or ($Value.failedCount -isnot [int] -and $Value.failedCount -isnot [long]) -or $Value.failedCount -ne 0 -or @($Value.checks).Count -ne $names.Count){throw 'RUNTIME_FIXTURE_COUNTS'}
    foreach($name in $names){$rows=@($Value.checks|Where-Object name -CEQ $name);if($rows.Count -ne 1 -or $rows[0].passed -isnot [bool] -or -not $rows[0].passed){throw 'RUNTIME_FIXTURE_CHECK_FAILED'}}
}
function Assert-PaperRuntimeControl($Value,[string]$Expected) {
    if($Value.version -cne 'PAPER_RUNTIME_CONTROL_V1' -or $Value.state -cne $Expected -or $Value.actionExecutionEnabled -isnot [bool] -or $Value.actionExecutionEnabled){throw 'RUNTIME_CONTROL_FAILED'}
    if($Value.databaseAuthenticationVerified -isnot [bool] -or $Value.databaseAuthenticationVerified){throw 'RUNTIME_CONTROL_AUTH_CLAIM'}
}
function Invoke-PaperRuntimeHandoffSequence([scriptblock]$Control,[scriptblock]$Restart,[byte[]]$Secret) {
    # Synthetic fixture only. An uncertain unlock is followed by a lock attempt, never an automatic unlock retry.
    if($null -eq $Secret -or $Secret.Length -ne 64){throw 'RUNTIME_SEQUENCE_INPUT'}
    & $Control 'STATUS' $null 'LOCKED'
    try {
        & $Control 'UNLOCK' $Secret 'UNLOCKED'
        & $Control 'UNLOCK' $Secret 'UNLOCKED'
        & $Control 'STATUS' $null 'UNLOCKED'
        & $Restart
        & $Control 'STATUS' $null 'LOCKED'
        & $Control 'UNLOCK' $Secret 'UNLOCKED'
    } finally { & $Control 'LOCK' $null 'LOCKED' }
    & $Control 'STATUS' $null 'LOCKED'
}
