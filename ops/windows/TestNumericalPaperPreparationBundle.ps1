#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [ValidateRange(10,300)][int]$TimeoutSeconds=120,
    [string]$ResumeReport
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalPaperPreparation.ps1')
. (Join-Path $PSScriptRoot 'NumericalPilotPolicyProposal.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'marketbrain-service\src\main\java\in\marketbrain\paper\PaperAccountEngineering.java'
$timer=[Diagnostics.Stopwatch]::StartNew();$id=[guid]::NewGuid().ToString('N')
$report=[ordered]@{version='NUMERICAL_PAPER_PREPARATION_BUNDLE_V1';status='RUNNING';runId=$id
    createdAtUtc=[DateTime]::UtcNow.ToString('o');elapsedSeconds=0;powerShellVersion=$PSVersionTable.PSVersion.ToString()
    manifest=$null;policyReview=$null;draftProposal=$null;process=$null;paperResult=$null;paperResultTextSha256=$null
    priorAcceptedEvidence='E71: evidence-store verification closed; no rerun'
    failure=$null;previousReportSha256=$null;executionMode='DRAFT_POLICY_AND_FIXED_SYNTHETIC_PAPER';events=@()}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-paper-preparation-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($path.Length+41 -ge 260){throw 'Choose a shorter output directory for atomic evidence checkpoints.'}
if(Test-Path -LiteralPath $path){throw 'Refusing to overwrite evidence.'}
function Update-PaperPreparationProgress([int]$Percent,[string]$Detail) {
    Write-Host "[$Percent%] $Detail"
    Write-Progress -Activity 'Numerical and paper preparation' -Status $Detail -PercentComplete $Percent
    $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;detail=$Detail})
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
}
try {
    Update-PaperPreparationProgress 0 'Reviewing draft policy; no provider, database, service or model calls.'
    $report.policyReview=Test-NumericalPilotPolicyProposal -RepositoryRoot $root
    Assert-PilotPolicyReview $report.policyReview
    $proposal=Join-Path $root 'ops\data\numerical-pilot-policy-proposal-v1.json'
    if((Get-Item -LiteralPath $proposal).Length -gt 1MB){throw 'Draft proposal exceeds bound.'}
    $report.draftProposal=Get-Content -LiteralPath $proposal -Raw | ConvertFrom-Json
    $revision=Invoke-EvaluationProcess 'git' @('-C',$root,'rev-parse','HEAD') 10
    if($revision.exitCode -ne 0 -or $revision.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Cannot identify repository revision.'}
    $manifest=[ordered]@{codeRevision=$revision.stdout.Trim()}
    $files=[ordered]@{source=$source;runner=$PSCommandPath;reviewer=(Join-Path $PSScriptRoot 'NumericalPaperPreparation.ps1')
        policyReviewer=(Join-Path $PSScriptRoot 'NumericalPilotPolicyProposal.ps1');proposal=$proposal
        hashHelper=(Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1');processHelper=(Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
        checkpointHelper=(Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
        prefitContract=(Join-Path $root 'ops\data\numerical-prefit-contract-v1.json')
        twoTrackPlan=(Join-Path $root 'ops\data\numerical-two-track-plan-v1.json')
        providerReview=(Join-Path $root 'docs\provider-pilot-readiness-20260919.md')}
    foreach($key in $files.Keys){$manifest[$key]=(Get-FileHash -LiteralPath $files[$key] -Algorithm SHA256).Hash}
    $report.manifest=$manifest
    if($ResumeReport){
        $savedItem=Get-Item -LiteralPath $ResumeReport
        if($savedItem.PSIsContainer -or $savedItem.Length -gt 8MB){throw 'Resume report must be a file <=8 MiB.'}
        $saved=Get-Content -LiteralPath $savedItem.FullName -Raw | ConvertFrom-Json
        if($saved.version -cne $report.version){throw 'Wrong saved bundle version.'}
        foreach($key in $manifest.Keys){if($saved.manifest.$key -cne $manifest[$key]){throw "Saved implementation mismatch: $key"}}
        if($saved.process.exitCode -ne 0 -or $saved.process.timedOut -or (Get-TenFeatureTextHash $saved.process.stdout) -cne $saved.paperResultTextSha256){throw 'No intact completed paper JVM output to reuse.'}
        $report.previousReportSha256=(Get-FileHash -LiteralPath $savedItem.FullName -Algorithm SHA256).Hash
        $report.executionMode='OFFLINE_SAVED_RESULT_REVIEW';$report.process=$saved.process
    } else {
        Update-PaperPreparationProgress 25 'Draft policy checked, not approved. Resolving native JDK 21+.'
        $java=Get-Command java -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $javac=Get-Command javac -CommandType Application -ErrorAction Stop | Select-Object -First 1
        if(-not $javac){throw 'Native JDK 21+ required; no automatic installation.'}
        Update-PaperPreparationProgress 40 'Running isolated paper-ledger fixtures; no active paper account or broker execution.'
        $report.process=Invoke-EvaluationProcess $java.Source @('-Xmx256m','--source','21',$source,'--synthetic-paper') $TimeoutSeconds
    }
    $report.paperResultTextSha256=Get-TenFeatureTextHash $report.process.stdout
    Save-NumericalHistoryReport $report $path -Compact
    if($report.process.stdout){try{$report.paperResult=$report.process.stdout | ConvertFrom-Json}catch{}}
    if($report.process.timedOut){throw 'Paper fixture JVM timed out; output preserved, no automatic retry.'}
    if($report.process.exitCode -ne 0){
        $detail=(@($report.process.stderr -split '\r?\n' | Where-Object {$_ -match '\S'}) | Select-Object -First 1)
        if(-not $detail){$detail='Inspect embedded stdout/stderr.'};if($detail.Length -gt 500){$detail=$detail.Substring(0,500)}
        throw "Paper fixture JVM exited with code $($report.process.exitCode): $detail"
    }
    Update-PaperPreparationProgress 85 'Checking paper cash/holdings conservation, lifecycle evidence and disabled release flags.'
    Assert-NumericalPaperPreparation $report.paperResult $report.policyReview
    $report.status='PREPARATION_CHECKS_PASSED_RUNTIME_RELEASE_BLOCKED'
    Update-PaperPreparationProgress 100 'Paper-core engineering passed; proposals remain drafts. No capture, market fitting or account activation.'
} catch {$report.status='FAILED';$report.failure=$_.Exception.Message}
finally {
    if($report.status -eq 'RUNNING'){$report.status='INTERRUPTED';$report.failure='Interrupted before completion.'}
    $timer.Stop();$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
    Write-Progress -Activity 'Numerical and paper preparation' -Completed
    Write-Progress -Activity 'Numerical evaluation engineering' -Completed
    Write-Host ('{0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this ONE file: $path"
}
if($report.status -ne 'PREPARATION_CHECKS_PASSED_RUNTIME_RELEASE_BLOCKED'){throw $report.failure}
