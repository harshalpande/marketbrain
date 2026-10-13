#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$AccessReportPath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Assert-PaperCustodyPath $OutputDirectory
[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-restriction-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version='PAPER_WRITER_RESTRICTION_PREPARATION_V1';status='RUNNING';revision=$null;manifest=@{};sourceHash=$null;sourceRunId=$null;events=@();tests=$null;proposedBlock=$null;firewallScope=$null;steps=@();findings=@();failureCode=$null;elapsedSeconds=0;databaseContacted=$false;databaseWritesPerformed=$false;realHbaRead=$false;hbaChanged=$false;firewallChanged=$false;writerLoginAttempted=$false;credentialsCreated=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Writer restriction preparation' -Status $Message -PercentComplete $Percent}
try {
    Stage 0 'Purpose: rehearse rules/recovery and collect missing firewall selectors. No configuration changes or database login.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'RESTRICTION_RUN_AS_WINDOWS_ADMINISTRATOR'}
    $dirty=@(git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'RESTRICTION_WORKTREE_REQUIRES_REVIEW'}
    $report.revision=(git -C $root rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'RESTRICTION_REVISION_UNAVAILABLE'}
    foreach($name in @('GetPaperWriterRestrictionPreparation.ps1','PaperWriterRestriction.ps1','TestPaperWriterRestrictionWorkflow.ps1','PaperWriterFirewallScope.ps1','PaperWriterAccessReview.ps1','PaperWriterPreflight.ps1','PaperWriterCustody.ps1','PaperStorageKey.ps1','NumericalHistoryEvidence.ps1')){
        $report.manifest[('ops/windows/'+$name)]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    # Frozen accepted snapshot, not a new claim that yesterday's route is still current.
    $expected='FFFF18099697737091CB1A8B031AA5ED8F6ACE4C9567DECA6F54C60A11962650'
    $inputPath=Assert-PaperCustodyPath $AccessReportPath
    $saved=Read-PaperRestrictionEvidence $inputPath $expected
    $report.sourceHash=$expected;$report.sourceRunId=$saved.runId
    Stage 15 'Accepted evidence matched. Testing only generated synthetic files and the proposed rule block.'
    $report.tests=& (Join-Path $PSScriptRoot 'TestPaperWriterRestrictionWorkflow.ps1') -PassThru
    if($report.tests.status -cne 'PASSED' -or -not $report.tests.fixtureCleanupComplete){throw 'RESTRICTION_REHEARSAL_FAILED'}
    $report.proposedBlock=New-PaperWriterRestrictionBlock
    Stage 40 'Reading saved candidate-rule selectors and current listener identity; bounded child process, no service restart.'
    $native=Invoke-PaperCatalogProcess (Join-Path $PSHOME 'pwsh.exe') @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'PaperWriterFirewallScope.ps1'),'-AccessReportPath',$inputPath,'-ExpectedHash',$expected) $root 180
    $report.steps+=@{stage='TARGETED_FIREWALL_SELECTORS';exitCode=$native.exitCode;timedOut=$native.timedOut;elapsedSeconds=$native.elapsedSeconds}
    # Retain the last complete JSON checkpoint even on interruption. No stderr or raw exceptions.
    if($native.stdout.Length -gt 32MB){throw 'RESTRICTION_CHILD_OUTPUT_LIMIT'}
    $malformed=$false;$count=0
    foreach($line in ($native.stdout -split '\r?\n')){
        if(-not $line.Trim()){continue};$count++
        if($count -gt 16 -or [Text.Encoding]::UTF8.GetByteCount($line) -gt 2MB){$malformed=$true;break}
        try {
            $v=$line|ConvertFrom-Json
            if($v.version -cne 'PAPER_FIREWALL_SCOPE_V1' -or $v.status -cnotin @('RUNNING','FAILED','SELECTORS_CAPTURED_REVIEW_REQUIRED') -or @($v.rules).Count -gt 200 -or $v.inspectedRuleCount -ne @($v.rules).Count){throw 'Bad child shape'}
            foreach($flag in @('configurationChanged','effectiveAccessProven','newRulesAssessed','truncated','ruleDriftDetected')){if($v.$flag -isnot [bool]){throw 'Bad child flags'}}
            if($v.configurationChanged -or $v.effectiveAccessProven -or $v.newRulesAssessed){throw 'Unsafe child shape'}
            $report.firewallScope=$v
        }catch{$malformed=$true;break}
    }
    Save
    if($native.exitCode -ne 0 -or $native.timedOut -or $malformed -or $null -eq $report.firewallScope -or $report.firewallScope.status -cne 'SELECTORS_CAPTURED_REVIEW_REQUIRED' -or $report.firewallScope.truncated -or $report.firewallScope.inspectedRuleCount -ne @($saved.firewall.rules).Count){throw 'RESTRICTION_SELECTOR_COLLECTION_INCOMPLETE'}
    $report.findings=@('REAL_HBA_STAGING_AND_AUTHENTICATION_NOT_TESTED','FIREWALL_SCOPE_REQUIRES_REVIEW','NEW_FIREWALL_RULES_SINCE_SNAPSHOT_NOT_ASSESSED','LIVE_IDENTITY_AND_HBA_HASH_REQUIRED_BEFORE_STAGING')
    if($report.firewallScope.ruleDriftDetected){$report.findings+='SAVED_RULE_METADATA_CHANGED'}
    if(@($report.firewallScope.rules|Where-Object {$_.missingSelectorFields.Count -gt 0}).Count){$report.findings+='FIREWALL_SELECTOR_FIELDS_UNAVAILABLE'}
    if(@($report.firewallScope.activeProfiles).Count -eq 0){$report.findings+='ACTIVE_CONNECTION_PROFILES_UNAVAILABLE'}
    if(@($report.firewallScope.listenerProcesses).Count -ne 1 -or @($report.firewallScope.listenerProcesses|Where-Object {$_.name -ine 'postgres.exe' -or -not $_.executablePath}).Count){$report.findings+='LISTENER_PROCESS_IDENTITY_REQUIRES_REVIEW'}
    Stage 90 'Rehearsal passed and metadata captured. Saving one report; real staging and activation remain blocked.'
    $report.status='PREPARATION_CAPTURED_STAGING_BLOCKED'
}catch{
    $report.status='FAILED';$report.failureCode='RESTRICTION_PREPARATION_FAILED'
    if($_.Exception.Message -cmatch '^RESTRICTION_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
}finally{
    Save;Write-Progress -Activity 'Writer restriction preparation' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s')
    Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'FAILED'){throw ('Preparation stopped: '+$report.failureCode)}
