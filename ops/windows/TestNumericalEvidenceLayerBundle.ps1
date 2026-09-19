#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SavedMappingReportPath='C:\MarketBrainData\Review\numerical-research-mapping-20260919-173811-99db869b03af.json',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [ValidateRange(10,300)][int]$TimeoutSeconds=120,
    [string]$ResumeReport
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvidenceLayer.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'marketbrain-service\src\main\java\in\marketbrain\training\NumericalEvidenceLedger.java'
$timer=[Diagnostics.Stopwatch]::StartNew();$id=[guid]::NewGuid().ToString('N')
$report=[ordered]@{version='NUMERICAL_EVIDENCE_LAYER_BUNDLE_V1';status='RUNNING';runId=$id;createdAtUtc=[DateTime]::UtcNow.ToString('o')
    elapsedSeconds=0;powerShellVersion=$PSVersionTable.PSVersion.ToString();manifest=$null;retrospective=$null
    process=$null;javaResult=$null;javaResultTextSha256=$null;failure=$null;previousReportSha256=$null
    executionMode='SAVED_SNAPSHOT_AND_SYNTHETIC_PERSISTENCE';events=@()}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-evidence-layer-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($path.Length+41 -ge 260){throw 'Choose a shorter output directory for atomic evidence checkpoints.'}
if(Test-Path -LiteralPath $path){throw 'Refusing to overwrite evidence.'}
function Update-EvidenceProgress([int]$Percent,[string]$Detail) {
    Write-Host "[$Percent%] $Detail"
    Write-Progress -Activity 'Numerical evidence layer' -Status $Detail -PercentComplete $Percent
    $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;detail=$Detail})
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
}
try {
    Update-EvidenceProgress 0 'Reading the accepted saved mapping; no service, database, feed or model calls.'
    $report.retrospective=Get-RetrospectiveSnapshotAssessment $SavedMappingReportPath
    if(-not $report.retrospective.sourceUnchanged){throw 'Saved input changed while being read.'}
    $revision=Invoke-EvaluationProcess 'git' @('-C',$root,'rev-parse','HEAD') 10
    if($revision.exitCode -ne 0 -or $revision.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Cannot identify repository revision.'}
    $manifest=[ordered]@{codeRevision=$revision.stdout.Trim()}
    $files=[ordered]@{source=$source;runner=$PSCommandPath;reviewer=(Join-Path $PSScriptRoot 'NumericalEvidenceLayer.ps1')
        hashHelper=(Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1');processHelper=(Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
        checkpointHelper=(Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1');contract=(Join-Path $root 'ops\data\numerical-prefit-contract-v1.json')}
    foreach($key in $files.Keys){$manifest[$key]=(Get-FileHash -LiteralPath $files[$key] -Algorithm SHA256).Hash}
    $report.manifest=$manifest
    if((Get-TenFeatureTextHash ([IO.File]::ReadAllText($files.contract).Replace("`r`n","`n"))) -cne '0ca5efab05b6fde03c16adb4181e31d63893e80fee8b71a63087eb35385a69d6'){throw 'Prefit contract changed; review required.'}
    if($ResumeReport){
        $savedItem=Get-Item -LiteralPath $ResumeReport
        if($savedItem.PSIsContainer -or $savedItem.Length -gt 8MB){throw 'Resume evidence must be a file <=8 MiB.'}
        $saved=Get-Content -LiteralPath $savedItem.FullName -Raw | ConvertFrom-Json
        if($saved.version -cne $report.version){throw 'Wrong saved report version.'}
        foreach($key in $manifest.Keys){if($saved.manifest.$key -cne $manifest[$key]){throw "Saved identity mismatch: $key"}}
        if($saved.process.exitCode -ne 0 -or $saved.process.timedOut -or (Get-TenFeatureTextHash $saved.process.stdout) -cne $saved.javaResultTextSha256){throw 'No intact completed JVM result to reuse.'}
        $report.previousReportSha256=(Get-FileHash -LiteralPath $savedItem.FullName -Algorithm SHA256).Hash
        $report.executionMode='OFFLINE_SAVED_RESULT_REVIEW';$report.process=$saved.process
    } else {
        Update-EvidenceProgress 25 'Saved snapshot assessed; resolving native JDK 21+. No rebuild or application restart.'
        $java=Get-Command java -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $javac=Get-Command javac -CommandType Application -ErrorAction Stop | Select-Object -First 1
        if(-not $javac){throw 'Native JDK 21+ required; no automatic installation.'}
        Update-EvidenceProgress 40 'Running 22 fixed synthetic persistence, quarantine, conflict and recovery checks.'
        $report.process=Invoke-EvaluationProcess $java.Source @('-Xmx256m','--source','21',$source,'--synthetic-evidence') $TimeoutSeconds
    }
    $report.javaResultTextSha256=Get-TenFeatureTextHash $report.process.stdout
    Save-NumericalHistoryReport $report $path -Compact
    if($report.process.stdout){try{$report.javaResult=$report.process.stdout | ConvertFrom-Json}catch{}}
    if($report.process.timedOut -or $report.process.exitCode -ne 0){throw 'Evidence JVM failed/timed out. Embedded output preserved; no automatic retry.'}
    Update-EvidenceProgress 85 'Independently verifying embedded ledger bytes, frame hashes, chain and safety flags.'
    Assert-EvidenceLayerResult $report.javaResult
    $report.status='EVIDENCE_ENGINEERING_PASSED_COLLECTION_AND_FIT_BLOCKED'
    Update-EvidenceProgress 100 'Evidence engineering passed. Collector disconnected; market predictive quality unmeasured.'
} catch {$report.status='FAILED';$report.failure=$_.Exception.Message}
finally {
    if($report.status -eq 'RUNNING'){$report.status='INTERRUPTED';$report.failure='Interrupted before completion.'}
    $timer.Stop();$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
    Write-Progress -Activity 'Numerical evidence layer' -Completed
    Write-Progress -Activity 'Numerical evaluation engineering' -Completed
    Write-Host ('{0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this ONE file: $path"
}
if($report.status -ne 'EVIDENCE_ENGINEERING_PASSED_COLLECTION_AND_FIT_BLOCKED'){throw $report.failure}
