#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationReportPath,
      [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
      [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterConnectionReview.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$secure=$null;$failureCode='REPORT_INITIALIZATION_FAILED'
$report=[ordered]@{version='PAPER_WRITER_CONNECTION_BUNDLE_V1';status='RUNNING';updatedAtUtc=$null;elapsedSeconds=0;revision=$null;manifest=@{};installationReportSha256=$null;target=$null;events=@();stage=$null;verification=$null;inventory=$null;reviewFindings=@();failure=$null;failureCode=$null;databaseWritesPerformed=$false;credentialsSaved=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-writer-connection-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,12))
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe report path.'}
function Save {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message;atUtc=[DateTime]::UtcNow.ToString('o')};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Paper writer connection review' -Status $Message -PercentComplete $Percent}
try {
    Stage 0 'Read-only authentication and database-access inventory. No login, password, grants or application changes.'
    $failureCode='INSTALLATION_REPORT_INVALID_OR_UNAVAILABLE'
    if((Get-Item -LiteralPath $InstallationReportPath).Length -gt 2097152){throw 'Report too large.'}
    $saved=Get-Content -LiteralPath $InstallationReportPath -Raw|ConvertFrom-Json
    Assert-PaperInstalledReport $saved
    $report.installationReportSha256=(Get-FileHash -LiteralPath $InstallationReportPath).Hash
    $report.target=$saved.target
    $failureCode='LOCAL_PREFLIGHT_FAILED'
    $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Revision unavailable.'}
    $dirty=@(& git -C $repo status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'Review local changes first.'}
    $files=@('ops/windows/GetPaperWriterConnectionReview.ps1','ops/windows/PaperWriterConnectionReview.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/NumericalHistoryEvidence.ps1')+@('writer-connection-review-v1.sql','writer-install-plan-v1.sql','writer-install-verify-v1.sql','approval-writer-v1.sql'|ForEach-Object {'marketbrain-service/src/main/resources/paper/'+$_})
    foreach($file in $files){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
    $psql=Join-Path $PostgreSqlBin 'psql.exe';if(-not (Test-Path -LiteralPath $psql -PathType Leaf)){throw 'psql missing.'}
    Write-Host "Target from accepted report: 127.0.0.1:$($saved.target.port) / $($saved.target.database)"
    $failureCode='TARGET_OR_CREDENTIAL_PROMPT_NOT_COMPLETED'
    if((Read-Host 'Confirm the database name') -cne $saved.target.database){throw 'Target not confirmed.'}
    $admin=Read-Host 'PostgreSQL administrator username'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'Invalid administrator name.'}
    $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString
    $password=[Net.NetworkCredential]::new('', $secure).Password;if(-not $password){throw 'Password required.'}
    Stage 35 'Checking staged permissions and reading bounded HBA/database metadata in one read-only transaction.'
    $failureCode='DATABASE_INSPECTION_FAILED'
    $sql=New-PaperConnectionReviewSql $saved.plan
    $r=Invoke-PaperInstallerPsql $psql $saved.target.database $saved.target.port $admin $password $sql
    $report.stage=@{exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;sqlStates=$r.sqlStates;assertionFailures=$r.assertionFailures;stderrCharacters=$r.stderrCharacters};Save
    if($r.exitCode -ne 0 -or $r.timedOut -or $r.stdout.Length -gt 2097152){throw 'Database inspection failed.'}
    $failureCode='OUTPUT_VALIDATION_FAILED'
    $rows=@($r.stdout.Trim() -split '\r?\n'|Where-Object {$_.Trim().Length})
    if($rows.Count -ne 2){throw 'Unexpected database output.'}
    $receipt=$rows[0]|ConvertFrom-Json;$inventory=$rows[1]|ConvertFrom-Json
    Assert-PaperWriterInstallReceipt $receipt 'Verify' $saved.plan.planHash
    Assert-PaperConnectionReview $inventory $saved.plan $saved.target.port
    $report.verification=$receipt;$report.inventory=$inventory
    Stage 85 'Inventory validated. Authentication applicability and application route still require review.'
    $report.reviewFindings=@(Get-PaperConnectionFindings $inventory)
    $report.status='CONNECTION_REVIEW_CAPTURED_LOGIN_DISABLED'
} catch {
    $report.status='FAILED';$report.failure='Connection inspection failed. Review safe stage diagnostics; no automatic retry or configuration change.'
    $report.failureCode=$failureCode
} finally {
    $password=$null;if($secure){$secure.Dispose()};Save
    Write-Progress -Activity 'Paper writer connection review' -Completed
    Write-Host ('[100%] {0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'FAILED'){throw $report.failure}
