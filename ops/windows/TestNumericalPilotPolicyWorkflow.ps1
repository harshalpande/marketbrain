[CmdletBinding()]
param([string]$RepositoryRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalPilotPolicyProposal.ps1')
$review=Test-NumericalPilotPolicyProposal -RepositoryRoot $RepositoryRoot
if($review.status -cne 'DRAFT_CONSISTENCY_PASSED_NOT_APPROVED' -or $review.checkCount -ne 29){throw 'Valid draft failed review.'}
$baseline=Get-Content -LiteralPath (Join-Path $RepositoryRoot 'ops/data/numerical-two-track-plan-v1.json') -Raw | ConvertFrom-Json
$prefit=Get-Content -LiteralPath (Join-Path $RepositoryRoot 'ops/data/numerical-prefit-contract-v1.json') -Raw | ConvertFrom-Json
$mutations=@(
    {param($p)$p.release.collectionAuthorized=$true},
    {param($p)$p.release.marketFitAuthorized=$true},
    {param($p)$p.release.liveExecutionAuthorized=$true},
    {param($p)$p.approvedByOwner=$true},
    {param($p)$p.existingEvidence.retrospectiveEligibleRows=600},
    {param($p)$p.existingEvidence.pointInTimeEligibleRows=600},
    {param($p)$p.captureProposal.dailyEventAgeSeconds=60},
    {param($p)$p.captureProposal.maxProviderCallsPerSession=1000},
    {param($p)$p.captureProposal.maxClockSkewMillis=60000},
    {param($p)$p.captureProposal.storage.rawPayloadRetentionEnabled=$true},
    {param($p)$p.evaluationProposal.minimumTrainingDates=80},
    {param($p)$p.evaluationProposal.previouslyInspectedRowsCanBeFinalTest=$true},
    {param($p)$p.evaluationProposal.uncertainty.independentRowResampling=$true},
    {param($p)$p.evaluationProposal.minimumAbsoluteMaeGainPpVersusEachBaseline=0},
    {param($p)$p.release.collectionAuthorized='false'},
    {param($p)$p.existingEvidence.mappingSha256='wrong'},
    {param($p)$p.evaluationProposal.minimumGapSessionsAtEachBoundary=0},
    {param($p)$p.evaluationProposal.actualExecutionCostPolicyApproved=$true}
)
$count=0
foreach($mutation in $mutations) {
    $changed=$review.proposal | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    & $mutation $changed
    $rejected=Test-NumericalPilotPolicyObject -Proposal $changed -BaselinePlan $baseline -PrefitContract $prefit
    if($rejected.status -cne 'DRAFT_CONSISTENCY_FAILED' -or $rejected.failedCount -lt 1){throw "Unsafe mutation accepted: $count"}
    $count++
}
foreach($source in $review.sourceFiles) {
    if((Get-FileHash -LiteralPath (Join-Path $RepositoryRoot $source.path) -Algorithm SHA256).Hash -cne $source.sha256){throw 'Policy workflow changed an input.'}
}
[pscustomobject]@{status='POLICY_WORKFLOW_PASSED';validDraftChecks=$review.checkCount;rejectedMutations=$count;sourceFilesUnchanged=$true;trainingAuthorized=$false;collectionAuthorized=$false}
