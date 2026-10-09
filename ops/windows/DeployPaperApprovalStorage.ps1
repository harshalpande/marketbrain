#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Deploy, [switch]$CreateKey, [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$AttachLedger=[bool]$Deploy;$RequireLedger=$true
. (Join-Path $PSScriptRoot 'PaperStorageKey.ps1')
$oldKeyFile=$env:MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$oldLocation=Get-Location
$oldToken=$env:MARKETBRAIN_PAPER_READ_TOKEN
$token=$null
$timer=[Diagnostics.Stopwatch]::StartNew()
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-account-read-'+[guid]::NewGuid().ToString('N')+'.json')
$report=[ordered]@{version='PAPER_ACCOUNT_READ_HANDOFF_V1';status='RUNNING';updatedAtUtc=$null;elapsedSeconds=0;revision=$null;deploymentRequested=[bool]$Deploy;events=@();checks=@();overview=$null;failure=$null;browserReview='PENDING_OWNER';accountMutationRequested=$false}
if($AttachLedger -or $RequireLedger){
    $report.version='PAPER_LEDGER_READ_HANDOFF_V1'
    $report.ledgerMigrationRequested=[bool]$AttachLedger
    $report.accountMutationRequested=[bool]$AttachLedger
    $report.legacyBalanceMutationRequested=$false
    $report.backupOwnerConfirmed=$false
    $report.preflight=$null
    $path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-ledger-read-'+[guid]::NewGuid().ToString('N')+'.json')
}
$report.version='PAPER_STORAGE_APPLICATION_HANDOFF_V1';$report.storageStatus=$null;$report.isolatedVerification=$null;$report.approvalMigrationRequested=[bool]$Deploy;$report.keySetupRequested=[bool]$Deploy;$report.keyBackupOwnerConfirmed=$false
$report.ledgerMigrationRequested=$false;$report.accountMutationRequested=$false;$report.applicationDatabaseWritesRequested=[bool]$Deploy
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-storage-application-'+[guid]::NewGuid().ToString('N')+'.json')
function Step([int]$Percent,[string]$Message) {
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    $report.events+=@{percent=$Percent;message=$Message;atUtc=[DateTime]::UtcNow.ToString('o')}
    Save-NumericalHistoryReport $report $path -Compact
    Write-Host "[$Percent%] $Message"
    Write-Progress -Activity 'Paper account read-only integration' -Status $Message -PercentComplete $Percent
}
function Docker([string[]]$Arguments,[int]$Limit=60) {
    if($Arguments[0] -eq 'compose'){$Arguments=@('compose','-f','compose.yaml','-f','compose.paper-storage.yaml')+@($Arguments|Select-Object -Skip 1)}
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$script:docker
    $p.StartInfo.WorkingDirectory=$repo;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    foreach($argument in $Arguments){[void]$p.StartInfo.ArgumentList.Add($argument)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$last=0
    try {
        [void]$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        while(-not $p.WaitForExit(250)) {
            if($watch.Elapsed.TotalSeconds -gt $Limit){$p.Kill($true);throw 'Docker command exceeded deadline. Inspect Docker state; no automatic retry.'}
            if($watch.Elapsed.TotalSeconds-$last -ge 10){$last=$watch.Elapsed.TotalSeconds;Write-Host ('Docker stage running: {0:N0}s / {1}s limit' -f $last,$Limit)}
        }
        if(-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)){throw 'Docker output drain deadline exceeded.'}
        $entry=@{arguments=($Arguments -join ' ');exitCode=$p.ExitCode;elapsedSeconds=$watch.Elapsed.TotalSeconds}
        # Only retain bounded output, with the read credential redacted. Never run compose config without --quiet.
        $output=($stdout.Result+"`n"+$stderr.Result).Replace($token,'[REDACTED]')
        $entry.output=$output.Substring([Math]::Max(0,$output.Length-12000));$report.checks+=@($entry)
        Save-NumericalHistoryReport $report $path -Compact
        if($p.ExitCode -ne 0){throw 'Docker stage failed; review saved output. No automatic retry.'}
    } finally { $p.Dispose() }
}
function Read-Http([string]$Url,[switch]$Authenticated) {
    $httpArgs=@{Uri=$Url;Method='Get';TimeoutSec=20;MaximumRedirection=0;SkipHttpErrorCheck=$true}
    if($Authenticated){$httpArgs.Headers=@{'X-MarketBrain-Paper-Read-Token'=$token}}
    Invoke-WebRequest @httpArgs
}
try {
    Set-Location -LiteralPath $repo
    Step 0 'Approval storage/key integration only. No new notifications, approvals, reservations or orders.'
    if($CreateKey -and -not $Deploy){throw 'CreateKey requires Deploy.'}
    if($AttachLedger -and -not $Deploy){throw 'AttachLedger requires Deploy. For a read-only retry use RequireLedger.'}
    if($Deploy -and -not $AttachLedger){throw 'This revision includes V27. Use Deploy with AttachLedger after backup and account preflight.'}
    $report.revision=(& git rev-parse HEAD | Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Cannot identify revision.'}
    if($Deploy) {
        $dirty=(& git status --porcelain | Out-String).Trim();if($LASTEXITCODE -ne 0 -or $dirty){throw 'Worktree is not clean. Preserve local changes before deployment.'}
        if((Read-Host 'Confirm all application jobs are idle. Type IDLE to rebuild service and UI') -cne 'IDLE'){throw 'Deployment cancelled.'}
    }
    $secure=Read-Host 'Enter the CURRENT private read token (32-128 letters, digits, underscore or hyphen); do not share it' -AsSecureString
    $token=[Net.NetworkCredential]::new('', $secure).Password
    if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'Invalid token format.'}
    if($Deploy) {
        $before=Read-Http 'http://127.0.0.1:8080/api/v1/paper/account/overview' -Authenticated
        if($before.StatusCode -ne 200){throw 'Existing account preflight failed. Use the current read token; no deployment started.'}
        $report.preflight=$before.Content|ConvertFrom-Json
        Assert-PaperAttachmentPreflight $report.preflight
        if($report.preflight.ledger.status -cne 'ATTACHED_READ_ONLY'){throw 'The accepted ledger attachment must already be present.'}
        Step 5 'Pristine attached account confirmed. V28 adds approval/delivery/key tables without changing cash.'
        if((Read-Host 'Confirm a current restorable database backup is retained. Type BACKED_UP (do not continue without one)') -cne 'BACKED_UP'){throw 'Database backup confirmation required before migration.'}
        $report.backupOwnerConfirmed=$true
        $beforeStorage=Read-Http 'http://127.0.0.1:8080/api/v1/paper/approval/storage' -Authenticated
        if($CreateKey -and -not (Test-Path -LiteralPath 'C:\MarketBrainData\Secrets\PaperApproval\delivery.key') -and $beforeStorage.StatusCode -ne 404){throw 'Key creation is allowed only before first storage deployment. Restore/review the original key instead.'}
        Step 7 'Running 12 new isolated migration/key/restart checks before application deployment.'
        $isolatedDirectory=Join-Path $OutputDirectory ('storage-preflight-'+[guid]::NewGuid().ToString('N'))
        try { & (Join-Path $PSScriptRoot 'TestPaperPersistenceBundle.ps1') -ApprovalStorage -BuildTimeoutSeconds 1800 -OutputDirectory $isolatedDirectory }
        finally { $files=@(Get-ChildItem -LiteralPath $isolatedDirectory -Filter 'paper-storage-*.json' -ErrorAction SilentlyContinue);if($files.Count -eq 1){$report.isolatedVerification=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json};Save-NumericalHistoryReport $report $path -Compact }
        if($report.isolatedVerification.status -cne 'ISOLATED_STORAGE_PASSED_APPLICATION_DEPLOYMENT_PENDING'){throw 'Storage preflight did not pass.'}
        $env:MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=Initialize-PaperStorageKey -Create:$CreateKey
        Write-Host 'Retain a secure backup of C:\MarketBrainData\Secrets\PaperApproval\delivery.key. Do NOT share it with the report.'
        if((Read-Host 'Confirm the encryption key has a secure recoverable backup. Type KEY_BACKED_UP') -cne 'KEY_BACKED_UP'){throw 'Key backup required; existing key retained, no deployment started.'}
        $report.keyBackupOwnerConfirmed=$true
        $script:docker=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source
        if(-not (Test-Path -LiteralPath $script:docker -PathType Leaf)){throw 'Docker executable unavailable.'}
        $env:MARKETBRAIN_PAPER_READ_TOKEN=$token
        Step 10 'Validating Compose privately; existing configuration and background schedules remain unchanged.'
        Docker @('compose','--env-file','.env','config','--quiet')
        Step 20 'Building service and UI; 30-minute build limit. No global Docker cleanup.'
        Docker @('compose','--env-file','.env','build','marketbrain-service','marketbrain-ui') 1800
        Step 45 'Recreating service and UI only; existing database and volumes retained.'
        Docker @('compose','--env-file','.env','up','-d','--no-deps','--force-recreate','marketbrain-service','marketbrain-ui') 180
    }
    Step 60 'Waiting for service health; at most 30 attempts with 10-second request deadlines.'
    $healthy=$false
    for($attempt=1;$attempt -le 30;$attempt++) {
        try { $health=Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -TimeoutSec 10 -MaximumRedirection 0; if($health.status -ceq 'UP'){$healthy=$true;break} } catch {}
        Write-Host "Health attempt $attempt/30 not ready."
        if($attempt -lt 30){Start-Sleep -Seconds 5}
    }
    if(-not $healthy){throw 'Health deadline exceeded; no account request sent.'}
    Step 75 'Checking unauthorized access and reading the account through the portal proxy.'
    foreach($port in @(8080,8081)) {
        $denied=Read-Http "http://127.0.0.1:$port/api/v1/paper/account/overview"
        $report.checks+=@{check="unauthenticated-$port";statusCode=[int]$denied.StatusCode}
        if($denied.StatusCode -ne 401){throw 'Unauthenticated access check failed (or read access disabled).'}
    }
    $response=Read-Http 'http://127.0.0.1:8081/api/v1/paper/account/overview' -Authenticated
    if($response.StatusCode -ne 200){throw 'Authenticated account read failed.'}
    $report.overview=$response.Content|ConvertFrom-Json
    Assert-PaperAccountOverview $report.overview
    if($AttachLedger -or $RequireLedger){
        if($report.overview.ledger.status -cne 'ATTACHED_READ_ONLY'){throw 'Ledger not attached or reconciliation required. Do not reset or reseed.'}
    }
    if(($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'Missing no-store response policy.'}
    $blocked=Read-Http 'http://127.0.0.1:8081/api/v1/system/status' -Authenticated
    if($blocked.StatusCode -ne 404){throw 'Portal proxy exposes an unexpected API route.'}
    $page=Read-Http 'http://127.0.0.1:8081/'
    if($page.StatusCode -ne 200 -or $page.Content -notmatch 'id="root"'){throw 'Portal page unavailable.'}
    $report.checks+=@{check='portal-proxy-and-page';status='PASSED'}
    $denied=Read-Http 'http://127.0.0.1:8080/api/v1/paper/approval/storage'
    if($denied.StatusCode -ne 401){throw 'Storage status anonymous-access check failed.'}
    $storageResponse=Read-Http 'http://127.0.0.1:8080/api/v1/paper/approval/storage' -Authenticated
    if($storageResponse.StatusCode -ne 200 -or ($storageResponse.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'Storage status read failed.'}
    $report.storageStatus=$storageResponse.Content|ConvertFrom-Json;Assert-PaperStorageStatus $report.storageStatus
    $report.status='READ_ONLY_INTEGRATION_VERIFIED_EXECUTION_BLOCKED'
    if($AttachLedger -or $RequireLedger){$report.status='LEDGER_ATTACHED_READ_ONLY_VERIFIED_EXECUTION_BLOCKED'}
    $report.status='APPLICATION_APPROVAL_STORAGE_VERIFIED_ACTIONS_DISABLED'
    Step 100 'Approval storage and key verified. Notification, approval and execution wiring remain disabled.'
    Write-Host 'Open http://127.0.0.1:8081 on this spare laptop. Enter the SAME token, read the account, then Clear and lock.'
    Write-Host 'The token remains in the running container, not .env. Future recreation without this token disables account access.'
} catch {
    $report.status='STOPPED_REVIEW_REQUIRED'
    # Never serialize request headers, credentials or raw exception request objects.
    $report.failure=if($token){$_.Exception.Message.Replace($token,'[REDACTED]')}else{$_.Exception.Message}
    Step 100 'Stopped. Evidence preserved; no automatic redeploy. If startup ran, inspect migration state before retrying.'
    throw $report.failure
} finally {
    $env:MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=$oldKeyFile
    $env:MARKETBRAIN_PAPER_READ_TOKEN=$oldToken;$token=$null;$secure=$null
    Set-Location -LiteralPath $oldLocation.Path
    Write-Progress -Activity 'Paper account read-only integration' -Completed
    Write-Host "Share this ONE file: $path"
}
