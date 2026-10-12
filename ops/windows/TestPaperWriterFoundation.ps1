#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory='C:\MarketBrainData\Review',[switch]$InspectLocalBoundary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew()
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,12)
$out=Assert-PaperCustodyPath $OutputDirectory
if(-not(Test-Path -LiteralPath $out -PathType Container)){[void](New-Item -ItemType Directory -Path $out -Force)}
$fixture=Join-Path $out ('writer-synthetic-'+$runId)
$reportPath=Join-Path $out ('paper-writer-foundation-'+$runId+'.json')
$checks=[Collections.Generic.List[string]]::new()
$report=[ordered]@{version='PAPER_WRITER_FOUNDATION_V1';status='FAILED';runId=$runId;observedAt=[DateTime]::UtcNow.ToString('o');powerShellVersion=$PSVersionTable.PSVersion.ToString();sourceHashes=@();checks=@();checkCount=0;elapsedSeconds=0;failureCode=$null;syntheticFixtureRemoved=$false;privateBoundary=$null;transportPolicy='PRIVATE_SAME_MACHINE_TLS_DEFERRED';databaseContacted=$false;databaseWritesPerformed=$false;realCredentialsCreated=$false;hbaChanged=$false;tlsConfigured=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;limitations=@('SYNTHETIC_CURRENT_WINDOWS_USER_ONLY','JAVA_CONNECTOR_NOT_RUNTIME_TESTED','NOT_APPLICATION_CREDENTIAL_HANDOFF','HBA_FIREWALL_AND_ACTUAL_SESSION_REVIEW_PENDING','NO_OTHER_USER_OR_BACKUP_RESTORE_PROOF')}
function Confirm-FoundationCheck([bool]$Condition,[string]$Name) {if(-not $Condition){throw ('CHECK_'+$Name)};$checks.Add($Name)}
function Confirm-FoundationReject([scriptblock]$Action,[string]$Name) {$rejected=$false;try{$null=& $Action}catch{$rejected=$true};Confirm-FoundationCheck $rejected $Name}
function Show-FoundationProgress([int]$Percent,[string]$Message){Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Writer security foundation (synthetic only)' -Status $Message -PercentComplete $Percent}
$secret=$null;$decoded=$null;$rng=$null;$original=$null;$tampered=$null;$phase='SOURCE'
try {
    Show-FoundationProgress 0 'No service restart, database login, administrator credential or model is used.'
    $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $manifest=[Collections.Generic.List[object]]::new()
    foreach($relative in @('ops/windows/TestPaperWriterFoundation.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/PaperWriterPrivateBoundary.ps1','ops/windows/PaperWriterPreflight.ps1','marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterConnector.java')){
        $manifest.Add([ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash})
    }
    $report.sourceHashes=$manifest.ToArray()
    $phase='FIXTURE'
    [void](New-Item -ItemType Directory -Path $fixture)
    Protect-PaperPrivateAcl $fixture -Directory
    $blob=Join-Path $fixture 'synthetic.dpapi'
    $secret=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($secret)
    Show-FoundationProgress 20 'Checking protected storage and same-user recovery with a random synthetic value.'
    $phase='ROUNDTRIP'
    Save-PaperWriterCustody $blob $secret
    $decoded=Read-PaperWriterCustody $blob
    Confirm-FoundationCheck ([Convert]::ToBase64String($decoded) -ceq [Convert]::ToBase64String($secret)) 'CURRENT_USER_ROUNDTRIP'
    [Array]::Clear($decoded,0,$decoded.Length);$decoded=$null
    Assert-PaperPrivateAcl $fixture;Assert-PaperPrivateAcl $blob
    Confirm-FoundationCheck $true 'PRIVATE_DIRECTORY_AND_FILE_ACL'
    $original=[IO.File]::ReadAllBytes($blob)
    Confirm-FoundationCheck ($original.Length -gt $secret.Length) 'ENCRYPTED_ENVELOPE_PRESENT'
    $phase='NEGATIVE_CHECKS'
    Confirm-FoundationReject {Save-PaperWriterCustody $blob $secret} 'EXISTING_FILE_NOT_OVERWRITTEN'
    Confirm-FoundationCheck ([Convert]::ToBase64String([IO.File]::ReadAllBytes($blob)) -ceq [Convert]::ToBase64String($original)) 'EXISTING_FILE_UNCHANGED'
    Confirm-FoundationReject {Read-PaperWriterCustody $blob 'WRONG_PURPOSE_V1'} 'WRONG_PURPOSE_REFUSED'
    Show-FoundationProgress 50 'Checking corruption, invalid inputs and unsafe permissions.'
    $tampered=[byte[]]$original.Clone();$tampered[$tampered.Length-1]=$tampered[$tampered.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($blob,$tampered)
    Confirm-FoundationReject {Read-PaperWriterCustody $blob} 'TAMPER_REFUSED'
    [IO.File]::WriteAllBytes($blob,(New-Object byte[] 4097))
    Confirm-FoundationReject {Read-PaperWriterCustody $blob} 'OVERSIZE_REFUSED'
    [IO.File]::WriteAllBytes($blob,(New-Object byte[] 1))
    Confirm-FoundationReject {Read-PaperWriterCustody $blob} 'TRUNCATED_REFUSED'
    [IO.File]::WriteAllBytes($blob,$original)
    Confirm-FoundationReject {Save-PaperWriterCustody (Join-Path $fixture 'invalid.dpapi') (New-Object byte[] 31)} 'INVALID_SECRET_SIZE_REFUSED'
    Confirm-FoundationReject {Assert-PaperCustodyPath '.\relative'} 'RELATIVE_PATH_REFUSED'
    Confirm-FoundationReject {Assert-PaperCustodyPath '\\server\share\blob'} 'NETWORK_PATH_REFUSED'
    Confirm-FoundationReject {Assert-PaperCustodyPath ($blob+':alternate')} 'ALTERNATE_STREAM_REFUSED'
    # An empty new fixture naturally inherits its parent's ACL. Do not request
    # SACL privileges or alter inheritance on an existing credential file.
    $inherited=Join-Path $fixture 'inherited-empty.dpapi'
    [void](New-Item -ItemType File -Path $inherited)
    Confirm-FoundationReject {Read-PaperWriterCustody $inherited} 'INHERITED_ACL_REFUSED'
    Remove-Item -LiteralPath $inherited
    $decoded=Read-PaperWriterCustody $blob
    Confirm-FoundationCheck ([Convert]::ToBase64String($decoded) -ceq [Convert]::ToBase64String($secret)) 'FIXTURE_RECOVERY_AFTER_NEGATIVES'
    Show-FoundationProgress 85 'All synthetic checks passed; removing only this run''s fixture.'
    $phase='CLEANUP'
    # Exact owned paths only, never recursive or an application/secret directory.
    if((Assert-PaperCustodyPath $fixture) -cne [IO.Path]::GetFullPath((Join-Path $out ('writer-synthetic-'+$runId)))){throw 'CLEANUP_SCOPE'}
    Remove-Item -LiteralPath $blob -Force
    Remove-Item -LiteralPath $fixture -Force
    $report.syntheticFixtureRemoved=$true
    $report.status='SYNTHETIC_CUSTODY_PASSED_ACTIVATION_BLOCKED'
    if($InspectLocalBoundary){
        $phase='PRIVATE_BOUNDARY'
        Show-FoundationProgress 90 'Inspecting selected local bindings and route classification; no connection or configuration change.'
        . (Join-Path $PSScriptRoot 'PaperWriterPrivateBoundary.ps1')
        $report.privateBoundary=Get-PaperWriterPrivateBoundary
        $report.status='FOUNDATION_CAPTURED_PRIVATE_BOUNDARY_REVIEW_REQUIRED'
        if($report.privateBoundary.status -ceq 'INCOMPLETE'){$report.status='FAILED';$report.failureCode=$report.privateBoundary.failureCode}
    }
}
catch {$report.status='FAILED';$report.failureCode=$phase+'_FAILED';if($_.Exception.Message -cmatch '^CHECK_[A-Z_]+$'){$report.failureCode=$_.Exception.Message};Write-Warning ('Stopped at '+$phase+'. Only synthetic evidence is retained; no automatic retry.')}
finally {
    foreach($buffer in @($secret,$decoded,$original,$tampered)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
    if($rng){$rng.Dispose()};$timer.Stop();$report.checks=$checks.ToArray();$report.checkCount=$checks.Count;$report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Progress -Activity 'Writer security foundation (synthetic only)' -Completed
    Write-Host ('[100%] '+$report.status+'; checks='+$checks.Count+'; elapsed='+[math]::Round($timer.Elapsed.TotalSeconds,2)+'s')
    Write-Host "Share this ONE file: $reportPath"
}
if($report.status -ceq 'FAILED'){throw ('Foundation rehearsal failed: '+$report.failureCode)}
