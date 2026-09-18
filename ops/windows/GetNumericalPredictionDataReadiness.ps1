#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$DatasetRunId,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [string]$ExistingAuditPath,
    [ValidateRange(10,120)][int]$RequestTimeoutSeconds=60
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalDataReadiness.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if ($DatasetRunId -eq [guid]::Empty) {throw 'Specify an explicit nonempty dataset run ID.'}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-data-readiness-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Evidence path exists.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_DATA_READINESS_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    datasetRunId=$DatasetRunId.ToString();mode=if($ExistingAuditPath){'SAVED_AUDIT'}else{'READ_ONLY_EXISTING_RUN_API'}
    sourceAuditHash=$null;sourceAudit=$null;assessment=$null;errorType=$null;events=[Collections.Generic.List[object]]::new()
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;assessmentSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalDataReadiness.ps1')).Hash
    safety='No model calls, training, provider calls, dataset writes, backfill, signals or orders. One saved run audit only. HTTP timeout does not cancel a server query; do not automatically retry. Future outcomes embedded for audit only, never inference input.'
}
function Save-ReadinessProgress([int]$Percent,[string]$Message) {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{percent=$Percent;atUtc=[DateTime]::UtcNow.ToString('o');message=$Message})
    Save-LlmInventoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 99 -Activity 'Numerical prediction data readiness' -Status $Message -PercentComplete $Percent
}
try {
    Save-ReadinessProgress 0 'Starting one-run data evidence collection; no LLM or training.'
    Write-Host "Single report: $path"
    if ($ExistingAuditPath) {
        $file=Get-Item -LiteralPath $ExistingAuditPath -ErrorAction Stop
        if ($file.PSIsContainer -or $file.Length -gt 5MB) {throw 'Expected a raw dataset audit JSON of at most 5 MiB.'}
        $report.sourceAuditHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $audit=[IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop
        Save-ReadinessProgress 30 'Loaded saved audit; no service call made.'
    } else {
        $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -Method Get -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
        if ((Get-ReadinessField $health 'status') -ne 'UP') {throw 'MarketBrain is not UP; no audit requested.'}
        Save-ReadinessProgress 20 'Health UP; requesting aggregate audit of the explicit persisted run.'
        $audit=Invoke-RestMethod -Uri ($base+'/api/v1/training/prototype-swing-dataset-audit?datasetRunId='+$DatasetRunId.ToString()) -Method Get -TimeoutSec $RequestTimeoutSeconds -MaximumRedirection 0 -ErrorAction Stop
    }
    $report.sourceAudit=$audit
    Save-ReadinessProgress 65 'Audit captured; reconciling counts and 20-session label availability.'
    $report.assessment=Measure-NumericalDataReadiness $audit $DatasetRunId
    $report.status=$report.assessment.status
    Save-ReadinessProgress 100 ('Readiness assessment complete: '+$report.status)
    $report.assessment | Select-Object status,featureEligiblePercent,fullyLabeledPercent,reported20SessionLabelCount,trainingAuthorized | Format-List
} catch {
    $report.status='FAILED_PARTIAL_REPORT';$report.errorType=$_.Exception.GetType().Name
    try {Save-ReadinessProgress 100 'Stopped; retain this report. No automatic retry or training.'} catch {Write-Warning 'Save failed; retain prior JSON/pending files.'}
    throw
} finally {Write-Progress -Id 99 -Activity 'Numerical prediction data readiness' -Completed;Write-Host "Share: $path"}
