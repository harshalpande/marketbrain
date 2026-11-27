#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$AcceptedInstallationSha256,
      [string]$InstallationPath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperPublisherCustody.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$id=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version='PAPER_PUBLISHER_CUSTODY_BUNDLE_V1';runId=$id;status='RUNNING';revision=$null;manifest=@{};failure=$null;failureCode=$null;custodyCreated=$null;custodyVerified=$false;custodyRetained=$null;databaseContacted=$false;databaseWritesRequested=$false;applicationRestartRequested=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
$phase='EVIDENCE'
$out=Assert-PaperCustodyPath $OutputDirectory;[void](New-Item -ItemType Directory -Path $out -Force)
$path=Join-Path $out ('paper-publisher-custody-{0}-{1}.json' -f (Get-Date -Format yyyyMMdd-HHmmss),$id.Substring(0,12))
function Stage($Percent,$Message){$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact;Write-Progress -Activity 'Publisher credential custody' -Status $Message -PercentComplete $Percent;Write-Host "[$Percent%] $Message"}
try {
    Stage 0 'Prepare a separate Windows-encrypted publisher credential. No database or application changes.'
    if(-not $InstallationPath){$InstallationPath=(Get-ChildItem -LiteralPath $out -File -Filter 'paper-publisher-install-*.json'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1).FullName}
    $accepted=Assert-PaperCustodyPath $InstallationPath;$file=Get-Item -LiteralPath $accepted
    if($file.Length -gt 2MB -or (Get-FileHash -LiteralPath $accepted).Hash -ine $AcceptedInstallationSha256){throw 'PUBLISHER_INSTALLATION_EVIDENCE_CHANGED'}
    $saved=Get-Content -LiteralPath $accepted -Raw|ConvertFrom-Json
    if($saved.version -cne 'PAPER_PUBLISHER_INSTALL_BUNDLE_V1' -or $saved.status -cne 'PUBLISHER_DISABLED_VERIFIED_CREDENTIALS_PENDING' -or $saved.commitOutcome -cne 'COMMITTED' -or $saved.verifyOnly -isnot [bool] -or $saved.verifyOnly){throw 'PUBLISHER_INSTALLATION_NOT_ACCEPTED'}
    foreach($flag in @('disabledStateVerified')){if($saved.catalog.$flag -isnot [bool] -or -not $saved.catalog.$flag){throw 'PUBLISHER_DISABLED_STATE_UNVERIFIED'}}
    foreach($flag in @('loginEnabled','actionExecutionEnabled')){if($saved.catalog.$flag -isnot [bool] -or $saved.catalog.$flag){throw 'PUBLISHER_INSTALLATION_UNSAFE'}}
    if($saved.runtimeConfigurationMatched -isnot [bool] -or -not $saved.runtimeConfigurationMatched -or $saved.cleanup.exitCode -ne 0 -or $saved.cleanup.timedOut){throw 'PUBLISHER_INSTALLATION_INCOMPLETE'}
    $report.acceptedInstallationSha256=$AcceptedInstallationSha256.ToUpperInvariant()
    $phase='SOURCE'
    $r=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'rev-parse','HEAD') $repo 10
    if($r.exitCode -ne 0 -or $r.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'REVISION_UNAVAILABLE'};$report.revision=$r.stdout.Trim()
    $r=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'status','--porcelain') $repo 10
    if($r.exitCode -ne 0 -or $r.stdout.Trim()){throw 'WORKTREE_NOT_CLEAN'}
    foreach($name in @('InitializePaperPublisherCredential.ps1','PaperPublisherCustody.ps1','PaperWriterCredential.ps1','PaperWriterCustody.ps1','PaperStorageKey.ps1','PaperWriterHbaStage.ps1','PaperWriterInstallation.ps1','PaperWriterConnectionReview.ps1','PaperWriterPreflight.ps1','NumericalHistoryEvidence.ps1')){$f='ops/windows/'+$name;$report.manifest[$f]=(Get-FileHash -LiteralPath (Join-Path $repo $f)).Hash}
    Stage 40 'Creating or verifying publisher-only DPAPI custody under the current Windows user.'
    $phase='LOCAL_CUSTODY'
    $result=Initialize-PaperPublisherCustody 'C:\MarketBrainData\Secrets\PaperPublisher' $AcceptedInstallationSha256
    foreach($flag in @('custodyCreated','custodyVerified','custodyRetained')){if($result[$flag] -isnot [bool]){throw 'PUBLISHER_CUSTODY_RESULT_INVALID'};$report[$flag]=$result[$flag]}
    if(-not $report.custodyVerified -or -not $report.custodyRetained){throw 'PUBLISHER_CUSTODY_UNVERIFIED'}
    $report.status='PUBLISHER_CUSTODY_VERIFIED_DATABASE_STAGING_PENDING'
}catch{$report.status='STOPPED_REVIEW_REQUIRED';$report.failureCode=$phase+'_FAILED';$report.failure='Credential custody stopped. Preserve existing files; do not delete or regenerate. No database changes were attempted.'}
finally{Stage 100 $report.status;Write-Progress -Activity 'Publisher credential custody' -Completed;Write-Host "Share this ONE file: $path"}
if($report.status -cne 'PUBLISHER_CUSTODY_VERIFIED_DATABASE_STAGING_PENDING'){throw 'Publisher custody needs review; share only the report, never the credential file.'}
