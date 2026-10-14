#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationReportPath,
      [ValidateSet('Stage','Verify')][string]$Mode='Verify',
      [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
      [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterCredential.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$timer=[Diagnostics.Stopwatch]::StartNew();$lock=$null;$payload=$null;$readback=$null;$entropy=$null;$verifier=$null;$password=$null;$secure=$null
$directory='C:\MarketBrainData\Secrets\PaperReviewWriter';$credential=Join-Path $directory 'writer.dpapi'
$report=[ordered]@{version='PAPER_WRITER_CREDENTIAL_BUNDLE_V1';status='RUNNING';mode=$Mode;updatedAtUtc=$null;elapsedSeconds=0;revision=$null;manifest=@{};installationReportSha256=$null;target=$null;events=@();steps=@();failureCode=$null;custodyCreated=$false;custodyVerified=$false;custodyRetained=$false;applyAttempted=$false;commitOutcome='NOT_ATTEMPTED';databaseContacted=$false;credentialMetadataMayHaveChanged=$false;accountRowsWritten=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;writerLoginEnabled=$null;helperLoginEnabled=$null;powerShellVersion=$PSVersionTable.PSVersion.ToString()}
$out=Assert-PaperCustodyPath $OutputDirectory
[void](New-Item -ItemType Directory -Path $out -Force)
$reportPath=Join-Path $out ('paper-writer-credential-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[Guid]::NewGuid().ToString('N').Substring(0,12))
$phase='EVIDENCE'
function Save-StageReport {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $reportPath -Compact}
function Show-StageProgress([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save-StageReport;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Disabled paper writer credential staging' -PercentComplete $Percent -Status $Message}
try {
    Show-StageProgress 0 'Credential staging only. Writer remains NOLOGIN. No application restart or account write.'
    $accepted=Assert-PaperCustodyPath $InstallationReportPath
    if((Get-Item -LiteralPath $accepted).Length -gt 2MB){throw 'INSTALLATION_REPORT_SIZE'}
    $report.installationReportSha256=(Get-FileHash -LiteralPath $accepted).Hash
    # Pin the installation whose target and grants were accepted. Never select a newest report by glob.
    if($report.installationReportSha256 -cne 'E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'){throw 'INSTALLATION_REPORT_NOT_ACCEPTED'}
    $saved=Get-Content -LiteralPath $accepted -Raw|ConvertFrom-Json;Assert-PaperInstalledReport $saved
    $report.target=$saved.target;$entropy=Get-PaperCredentialEntropy $saved
    $phase='PREFLIGHT'
    $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'REVISION_UNAVAILABLE'}
    $dirty=@(& git -C $repo status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'WORKTREE_NOT_CLEAN'}
    foreach($relative in @('ops/windows/SetPaperWriterCredential.ps1','ops/windows/PaperWriterCredential.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperWriterHbaStage.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/PaperWriterConnectionReview.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/src/main/resources/paper/writer-install-plan-v1.sql','marketbrain-service/src/main/resources/paper/writer-install-verify-v1.sql','marketbrain-service/src/main/resources/paper/approval-writer-v1.sql')){
        $report.manifest[$relative]=(Get-FileHash -LiteralPath (Join-Path $repo $relative)).Hash
    }
    $psql=Join-Path $PostgreSqlBin 'psql.exe';if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'PSQL_NOT_FOUND'}
    $phase='CONFIRMATION'
    Write-Host "Target: 127.0.0.1:$($saved.target.port) / $($saved.target.database). Existing application credentials are not changed."
    if((Read-Host 'Confirm database name') -cne $saved.target.database){throw 'TARGET_NOT_CONFIRMED'}
    if($Mode -ceq 'Stage' -and (Read-Host 'Type STAGE_DISABLED_WRITER to create/reuse protected custody and stage only its password') -cne 'STAGE_DISABLED_WRITER'){throw 'STAGING_NOT_CONFIRMED'}
    $phase='CUSTODY'
    $null=Assert-PaperCustodyPath $credential
    if(-not(Test-Path -LiteralPath $directory)){
        if($Mode -cne 'Stage'){throw 'CUSTODY_MISSING'}
        [void](New-Item -ItemType Directory -Path $directory);Protect-PaperHbaBackupAcl $directory -Directory
    }
    Assert-PaperPrivateAcl $directory
    # Exclusive handle across the entire workflow. Retain the empty lock file; no remove/recreate race.
    $lockPath=Join-Path $directory 'credential.lock';$null=Assert-PaperCustodyPath $lockPath
    $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
    if(Test-Path -LiteralPath $credential){$payload=Read-PaperCredential $credential $entropy}
    else {
        if($Mode -cne 'Stage'){throw 'CUSTODY_MISSING'}
        $payload=New-Object byte[] 48;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try {$rng.GetBytes($payload)} finally {$rng.Dispose()}
        Save-PaperCredential $credential $payload $entropy;$report.custodyCreated=$true
    }
    $readback=Read-PaperCredential $credential $entropy
    if([Convert]::ToBase64String($payload) -cne [Convert]::ToBase64String($readback)){throw 'CUSTODY_READBACK_MISMATCH'}
    $report.custodyVerified=$true;$report.custodyRetained=$true;$verifier=New-PaperCredentialVerifier $readback
    Show-StageProgress 25 'Protected same-user custody verified. Next: fresh database guards and rollback rehearsal.'
    $phase='ADMIN_CREDENTIAL'
    $admin=Read-Host 'PostgreSQL administrator username'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'ADMIN_NAME_INVALID'}
    $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString
    $password=[Net.NetworkCredential]::new('', $secure).Password;if(-not $password){throw 'ADMIN_PASSWORD_REQUIRED'}
    $phase='DATABASE'
    $execute={param($operation)
        $percent=40+10*@($report.steps).Count
        Show-StageProgress $percent ("Database $operation; bounded metadata checks, no account rows or login enablement.")
        $sql=New-PaperCredentialSql $operation $saved.plan $verifier
        if($operation -ceq 'Stage'){$report.applyAttempted=$true;$report.credentialMetadataMayHaveChanged=$true;$report.commitOutcome='UNKNOWN_VERIFY_BEFORE_RETRY';Save-StageReport}
        $report.databaseContacted=$true
        try {$native=Invoke-PaperInstallerPsql $psql $saved.target.database $saved.target.port $admin $password $sql} finally {$sql=$null}
        $report.steps+=@{phase=$operation;exitCode=$native.exitCode;timedOut=$native.timedOut;elapsedSeconds=$native.elapsedSeconds;sqlStates=$native.sqlStates;assertionFailures=$native.assertionFailures;inputLocations=$native.inputLocations;stderrCharacters=$native.stderrCharacters}
        Save-StageReport
        if($native.exitCode -ne 0 -or $native.timedOut -or $native.stdout.Length -gt 8192){throw 'DATABASE_STEP_FAILED'}
        $value=$native.stdout.Trim()|ConvertFrom-Json
        Assert-PaperCredentialReceipt $value $operation $saved.plan.planHash
        # Only validated, nonsecret fields are exported; no raw native output or SQL.
        $report.writerLoginEnabled=$value.writerLoginEnabled;$report.helperLoginEnabled=$value.helperLoginEnabled
        return $value
    }
    $report.commitOutcome=Invoke-PaperCredentialSequence $execute $saved.plan.planHash -VerifyOnly:($Mode -ceq 'Verify')
    $report.status='WRITER_CREDENTIAL_STAGED_LOGIN_DISABLED'
    Show-StageProgress 100 'Credential verified; writer and helper remain NOLOGIN. Application authentication is the next gate.'
} catch {
    $report.status='STOPPED_REVIEW_REQUIRED';$report.failureCode=$phase+'_FAILED'
    if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]{3,100}$'){$report.failureCode=$_.Exception.Message}
    Write-Warning 'Stopped safely. Preserve protected custody. Do not delete/regenerate it or retry with another password. Share the report.'
} finally {
    if($lock){$lock.Dispose()};foreach($bytes in @($payload,$readback,$entropy)){if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
    $verifier=$null;$password=$null;if($secure){$secure.Dispose()};Save-StageReport
    Write-Progress -Activity 'Disabled paper writer credential staging' -Completed
    Write-Host ('[100%] {0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this ONE file: $reportPath"
    Write-Host 'Never share the Secrets directory. No HBA, firewall, Tailscale or application setting was changed.'
}
if($report.status -cne 'WRITER_CREDENTIAL_STAGED_LOGIN_DISABLED'){throw ('Credential staging stopped: '+$report.failureCode)}
