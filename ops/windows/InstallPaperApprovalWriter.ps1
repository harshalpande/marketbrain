#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply,[string]$VerifyReportPath,
      [ValidatePattern('^[a-z][a-z0-9_]{0,62}$')][string]$DatabaseName='marketbrain',
      [ValidateRange(1,65535)][int]$DatabasePort=5432,
      [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
      [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$secure=$null;$admin=$null
$report=[ordered]@{version='PAPER_WRITER_INSTALL_BUNDLE_V1';status='RUNNING';updatedAtUtc=$null;elapsedSeconds=0;revision=$null;manifest=@{};events=@();steps=@();target=@{host='127.0.0.1';port=$DatabasePort;database=$DatabaseName};plan=$null;rehearsal=$null;applyReceipt=$null;verification=$null;failure=$null;backupConfirmed=$false;maintenanceConfirmed=$false;targetConfirmed=$false;rolesApproved=$false;rehearsalRollbackVerified=$false;applyRequested=[bool]$Apply;applyAttempted=$false;commitOutcome='NOT_ATTEMPTED';applicationWriterActivated=$false;actionExecutionEnabled=$false;credentialsSaved=$false}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-writer-install-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,12))
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe or existing report path.'}
function Save {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message;atUtc=[DateTime]::UtcNow.ToString('o')};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Guarded paper writer installation' -Status $Message -PercentComplete $Percent}
function Run-Sql([string]$Phase,$Envelope) {
    $sql=New-PaperWriterInstallSql $Phase $Envelope
    $r=Invoke-PaperInstallerPsql $psql $DatabaseName $DatabasePort $admin $password $sql
    $report.steps+=@{phase=$Phase;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;sqlStates=$r.sqlStates;assertionFailures=$r.assertionFailures;stderrCharacters=$r.stderrCharacters};Save
    if($r.exitCode -ne 0 -or $r.timedOut -or $r.stdout.Length -gt 500000){throw 'Database stage failed; do not automatically retry.'}
    return ($r.stdout.Trim()|ConvertFrom-Json)
}
try {
    Stage 0 'Permission installation only. No application restart, account mutation, credential activation or trading.'
    if($Apply -and $VerifyReportPath){throw 'Apply and VerifyReportPath cannot be combined.'}
    $psql=Join-Path $PostgreSqlBin 'psql.exe'
    if(-not (Test-Path -LiteralPath $psql -PathType Leaf)){throw 'PostgreSQL 18 psql.exe not found. Provide its bin directory.'}
    $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Cannot identify revision.'}
    $dirty=@(& git -C $repo status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'Preserve/review local changes first.'}
    foreach($file in @('ops/windows/InstallPaperApprovalWriter.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/NumericalHistoryEvidence.ps1')+@('approval-writer-v1.sql','writer-install-plan-v1.sql','writer-install-guard-v1.sql','writer-install-grants-v1.sql','writer-install-owner-v1.sql','writer-install-verify-v1.sql'|ForEach-Object {'marketbrain-service/src/main/resources/paper/'+$_})){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
    Write-Host "Target: 127.0.0.1:$DatabasePort / $DatabaseName. Confirm this is MarketBrain's actual application database."
    if((Read-Host "Type the database name $DatabaseName to confirm the target") -cne $DatabaseName){throw 'Target not confirmed.'};$report.targetConfirmed=$true
    $admin=Read-Host 'PostgreSQL administrator username (password is prompted separately; never share it)'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'Administrator username needs manual review.'}
    $secure=Read-Host 'PostgreSQL administrator password' -AsSecureString;$password=[Net.NetworkCredential]::new('', $secure).Password
    if(-not $password){throw 'Administrator password required.'}
    if($VerifyReportPath) {
        if((Get-Item -LiteralPath $VerifyReportPath).Length -gt 2097152){throw 'Verification report exceeds two MiB limit.'}
        $saved=Get-Content -LiteralPath $VerifyReportPath -Raw|ConvertFrom-Json
        if($saved.version -cne $report.version -or $saved.target.database -cne $DatabaseName -or $saved.target.port -ne $DatabasePort){throw 'Verification report target mismatch.'}
        Assert-PaperWriterInstallPlan $saved.plan;$report.plan=$saved.plan
        Stage 60 'Read-only verification of saved installation. No changes or automatic recovery.'
        $report.verification=Run-Sql 'Verify' $saved.plan
        Assert-PaperWriterInstallReceipt $report.verification 'Verify' $saved.plan.planHash
        $report.commitOutcome='STAGED_STATE_VERIFIED';$report.status='STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED'
    } else {
        Stage 15 'Reading administrator catalog plan; no application rows or password hashes.'
        $report.plan=Run-Sql 'Plan' $null;Save;Assert-PaperWriterInstallPlan $report.plan
        if($report.plan.plan.database -cne $DatabaseName){throw 'Database target mismatch.'}
        Write-Host ('Plan fingerprint: '+$report.plan.planHash)
        Write-Host 'Existing roles whose TEMP access will be explicitly preserved (including non-login group roles):'
        $report.plan.plan.roles|Where-Object {$_.temp -and -not $_.explicitTemp}|Select-Object roleName,login|Format-Table -AutoSize|Out-Host
        Write-Host 'Change: remove PUBLIC TEMP on this database only. Future roles will need explicit TEMP grants or membership.'
        Write-Host 'Create two restricted NOLOGIN roles and two review functions. No writer password, login or application wiring.'
        if(-not $Apply){$report.status='INSTALLATION_PLAN_CAPTURED_NO_CHANGES'}
        else {
            if((Read-Host 'Confirm a current restorable database backup is retained. Type BACKED_UP') -cne 'BACKED_UP'){throw 'Backup confirmation required.'};$report.backupConfirmed=$true
            if((Read-Host 'Pause application jobs and other administrator/schema changes for this short maintenance window. Type IDLE') -cne 'IDLE'){throw 'Maintenance window required.'};$report.maintenanceConfirmed=$true
            if((Read-Host 'Approve the displayed role list and targeted permission change. Type APPROVE_ROLES') -cne 'APPROVE_ROLES'){throw 'Permission plan not approved.'};$report.rolesApproved=$true
            Stage 35 'Rehearsing the exact transaction and permission assertions, then rolling it back.'
            $report.rehearsal=Run-Sql 'Rehearse' $report.plan;Assert-PaperWriterInstallReceipt $report.rehearsal 'Rehearse' $report.plan.planHash
            $after=Run-Sql 'Plan' $null;Assert-PaperWriterInstallPlan $after
            if($after.planHash -cne $report.plan.planHash){throw 'Rehearsal rollback or catalog stability not proven.'};$report.rehearsalRollbackVerified=$true
            Stage 65 'Rehearsal passed and original catalog restored. Final confirmation precedes commit.'
            if((Read-Host ('To commit this exact plan type INSTALL '+$report.plan.planHash)) -cne ('INSTALL '+$report.plan.planHash)){throw 'Installation not confirmed.'}
            $report.applyAttempted=$true;$report.commitOutcome='UNKNOWN_VERIFY_BEFORE_RETRY';Save
            $report.applyReceipt=Run-Sql 'Apply' $report.plan;Assert-PaperWriterInstallReceipt $report.applyReceipt 'Apply' $report.plan.planHash
            $report.commitOutcome='COMMIT_ACKNOWLEDGED_READBACK_PENDING';Save
            Stage 85 'Checking installed permissions on a fresh read-only administrator connection.'
            $report.verification=Run-Sql 'Verify' $report.plan;Assert-PaperWriterInstallReceipt $report.verification 'Verify' $report.plan.planHash
            $report.commitOutcome='COMMITTED_AND_VERIFIED';$report.status='STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED'
        }
    }
} catch {
    $report.status='STOPPED_REVIEW_REQUIRED'
    $report.failure='Stopped during '+[string]$report.events[-1].message+' See stage SQLSTATE/exit codes. Never repeat Apply blindly after an attempted commit.'
    Write-Warning 'Stopped safely for review. A failed/lost commit acknowledgement may need read-only verification; do not reset or reinstall.'
} finally {
    $password=$null;$admin=$null;if($secure){$secure.Dispose()};$secure=$null
    Stage 100 $report.status;Write-Progress -Activity 'Guarded paper writer installation' -Completed
    Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'STOPPED_REVIEW_REQUIRED'){throw 'Installation requires review. Share the saved report; do not automatically retry.'}
