# Embedded after the recovery functions by Build-DenialRecoveryJob.ps1.
$report=@{version=1;test='PINNED_DENIAL_RECOVERY';mode=$Mode;passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;failure=$null;cleanupFailure=$null;backupVerified=$false;instrumentationInstalled=$false;archivedMarkersCleared=$false;guardRegistered=$false;guardRemoved=$false;startAttempts=0;transportObserved=$false;finalStoppedAndDisabled=$false}
$ctx=@{root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1';work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1';taskName='MarketBrain-Gateway-Supervisor-v1';resultPath=$ResultPath;guardXmlHash=$null}
$clock=[Diagnostics.Stopwatch]::StartNew()
try {
    if($Mode -ceq 'FailureFixture'){throw 'RECOVERY_DELIBERATE_FAILURE_NO_GATEWAY_ACCESS'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'RECOVERY_ELEVATED_SESSION_REQUIRED'}}finally{$identity.Dispose()}
    $ctx.runId=Split-Path (Split-Path $ResultPath -Parent) -Leaf
    if($ctx.runId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'RECOVERY_JOB_ID_REQUIRED'}
    $ctx.archive=Join-Path $ctx.root ('denial-recovery-'+$ctx.runId)
    $ctx.guardName='MarketBrain-Denial-Guard-'+$ctx.runId
    $prior='649710f6-e95b-4ebc-831b-60a99d22ac69'
    $priorArchive=Join-Path $ctx.root ('denial-recovery-'+$prior)
    if($Mode -ceq 'Observe' -and (Test-Path -LiteralPath $priorArchive)){
        $g=Get-ScheduledTask -TaskName ('MarketBrain-Denial-Guard-'+$prior) -TaskPath '\' -ErrorAction Stop
        $task=Get-ScheduledTask -TaskName $ctx.taskName -TaskPath '\'
        $report.guardInspection=@{
            priorJob=$prior;state=[string]$g.State;userId=$g.Principal.UserId;logonType=[string]$g.Principal.LogonType;runLevel=[string]$g.Principal.RunLevel
            actions=@($g.Actions|ForEach-Object {@{execute=$_.Execute;argumentCharacters=$_.Arguments.Length}})
            triggers=@($g.Triggers|ForEach-Object {@{startBoundary=$_.StartBoundary;enabled=$_.Enabled;class=$_.CimClass.CimClassName}})
            settings=@{enabled=$g.Settings.Enabled;startWhenAvailable=$g.Settings.StartWhenAvailable;disallowStartIfOnBatteries=$g.Settings.DisallowStartIfOnBatteries;stopIfGoingOnBatteries=$g.Settings.StopIfGoingOnBatteries}
            gatewayState=[string]$task.State;gatewayEnabled=$task.Settings.Enabled
            guardFired=(Test-Path -LiteralPath (Join-Path $priorArchive 'guard-fired.json'))
            manifestHash=(Get-FileHash -LiteralPath (Join-Path $ctx.root 'manifest.json')).Hash
        }
        $report.status='GUARD_INSPECTION_ONLY_RECOVERY_PENDING';$report.passed=$true
        return
    }
    if($Mode -ceq 'Apply' -and (Test-Path -LiteralPath $priorArchive)){
        Resume-DenialRecoveryCapture $ctx $acceptedRecoveryReceipt $report
        $report.passed=$report.transportObserved -and $report.finalStoppedAndDisabled -and $report.guardRemoved -and -not $report.cleanupFailure
        $report.status=if($report.passed){'DENIAL_RECOVERY_CAPTURE_PASSED_GATEWAY_STOPPED'}else{'DENIAL_RECOVERY_REVIEW_REQUIRED'}
        if(-not $report.passed){throw 'RECOVERY_RESUME_INCOMPLETE'}
        return
    }
    $before=Get-DenialRecoveryPreflight (Read-BoundedJson (Join-Path $ctx.work 'status.json'))
    $report.preflight=$before
    if(-not $before.readyForReviewedRecovery){throw 'RECOVERY_PREFLIGHT_FAILED'}
    # Snapshot hash map embedded at build time from the accepted remote preflight.
    foreach($name in $acceptedRecoveryReceipt.hashes.Keys){if($before.hashes[$name] -cne $acceptedRecoveryReceipt.hashes[$name]){throw 'RECOVERY_ACCEPTED_RECEIPT_DRIFT'}}
    if($before.task.lastRunUtc -cne $acceptedRecoveryReceipt.task.lastRunUtc){throw 'RECOVERY_ACCEPTED_TASK_DRIFT'}
    if($Mode -ceq 'Observe'){$report.passed=$true;$report.status='RECOVERY_PREFLIGHT_PASSED_APPLY_PENDING'}
    else {
        $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(30);$client.MaxResponseContentBufferSize=65536
        try{$bytes=$client.GetByteArrayAsync('https://raw.githubusercontent.com/harshalpande/marketbrain/c738a2abdfd941a2939911e0d904b8e28bd9c57a/ops/windows/PaytmSupervisorTransport.ps1').GetAwaiter().GetResult()}finally{$client.Dispose()}
        if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne '40343DDDBF1063ACE422922D5D4DAD98B126B04C53ECA40790B174ECA8C9CBCD'){throw 'RECOVERY_PATCH_HASH_MISMATCH'}
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::UTF8.GetString($bytes),[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'RECOVERY_PATCH_PARSE_FAILED'}
        Invoke-DenialRecoveryApply $ctx $before $bytes $report
        $report.passed=$report.transportObserved -and $report.finalStoppedAndDisabled -and $report.guardRemoved -and -not $report.cleanupFailure
        $report.status=if($report.passed){'DENIAL_RECOVERY_CAPTURE_PASSED_GATEWAY_STOPPED'}else{'DENIAL_RECOVERY_REVIEW_REQUIRED'}
    }
} catch {
    $report.passed=$false
    $report.failure=if($_.Exception.Message -cmatch '^RECOVERY_[A-Z_]+$'){$_.Exception.Message}else{'RECOVERY_'+$_.Exception.GetType().Name}
    $report.failureLine=$_.InvocationInfo.ScriptLineNumber
} finally {if($ctx.guardVerification){$report.guardVerification=$ctx.guardVerification};$report.elapsedSeconds=$clock.Elapsed.TotalSeconds;Save-DenialRecoveryResult $ctx $report}
if(-not $report.passed){exit 1}
