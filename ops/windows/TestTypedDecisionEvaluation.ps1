# Offline regression checks. No database, network, model or service invocation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
function Assert-Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
Write-Progress -Activity 'Offline decision evaluation tests' -Status 'Grammar and policy' -PercentComplete 10
Write-Host '[10%] Checking independent grammar and policy...'
$candidate = [pscustomobject]@{
    candidateId = 'CANDIDATE_001'; javaDecision = 'REJECT'; javaRiskBucket = 'HIGH'
    javaTopPickEligibility = 'BLOCKED'; javaScoreCapHint = 'HARD_CAP_69'; hardExclusionReason = 'NONE'
}
$grammar = @'
root ::= candidate-id decision
candidate-id ::= "\"CANDIDATE_" digit digit digit "\""
decision ::= "\"REJECT\"" | "\"WATCHLIST\"" | "\"SHORTLIST\"" | "\"TOP_PICK\""
digit ::= [0-9]
'@
$independent = New-IndependentDecisionGrammar $candidate $grammar
Assert-Check ($independent.Contains('candidate-id ::= "\"CANDIDATE_001\""')) 'Identity binding failed'
$candidate.javaDecision = 'TOP_PICK'
Assert-Check ($independent -ceq (New-IndependentDecisionGrammar $candidate $grammar)) 'Java decision leaked into grammar'
Assert-Check ($independent.Contains('SHORTLIST') -and $independent.Contains('WATCHLIST')) 'Choice removed'
$decision = [pscustomobject]@{
    decision='SHORTLIST'; riskBucket='HIGH'; scoreBand='HIGH'; primaryReasonCode='RECOVERY_SETUP'
}
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT').Count -eq 0) 'Caution incorrectly forced rejection'
$decision.decision = 'TOP_PICK'
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT') -contains 'HARD_CAP_69_TOP_PICK_VIOLATION') 'Cap not enforced'
$decision.decision = 'REJECT'
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT') -contains 'REJECT_WITH_HIGH_SCORE_BAND') 'Invalid pairing accepted'
$decision.riskBucket = 'BLOCKED'; $decision.scoreBand = 'LOW'
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT') -contains 'BLOCKED_WITHOUT_HARD_EXCLUSION') 'Caution became hard exclusion'
$candidate.hardExclusionReason = 'MISSING_OR_INVALID_REQUIRED_FEATURES'
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT').Count -eq 0) 'Hard exclusion rejection blocked'
$decision.decision = 'WATCHLIST'
Assert-Check (@(Get-DecisionPolicyFailures $candidate $decision 'INDEPENDENT') -contains 'HARD_EXCLUSION_NOT_RESPECTED') 'Hard exclusion bypassed'
Write-Progress -Activity 'Offline decision evaluation tests' -Status 'Metric denominators' -PercentComplete 60
Write-Host '[60%] Checking missing labels, invalid outputs and reject-all metrics...'
$attempts = @(
    [pscustomobject]@{ businessValid=$true; modelDecision='REJECT'; javaDecision='SHORTLIST'; targetNetReturnPercent=10; targetBenchmarkExcessReturnPercent=5; targetMaximumDrawdownPercent=2; evidenceCategory='OPPORTUNITY'; elapsedMillis=100 },
    [pscustomobject]@{ businessValid=$false; modelDecision='TOP_PICK'; javaDecision='REJECT'; targetNetReturnPercent=20; targetBenchmarkExcessReturnPercent=15; targetMaximumDrawdownPercent=4; evidenceCategory='CAUTION'; elapsedMillis=200 },
    [pscustomobject]@{ businessValid=$true; modelDecision='REJECT'; javaDecision='REJECT'; targetNetReturnPercent=$null; targetBenchmarkExcessReturnPercent=$null; targetMaximumDrawdownPercent=$null; evidenceCategory='AVOID'; elapsedMillis=300 }
)
$metrics = Get-TypedDecisionEvaluation $attempts
Assert-Check ($metrics.modelSelectedCount -eq 0) 'Invalid output counted as selected'
Assert-Check ($metrics.modelPositiveOutcomeRecallPercent -eq 0) 'Reject-all incorrectly scored'
Assert-Check ($metrics.javaPositiveOutcomeRecallPercent -eq 50) 'Incorrect Java recall denominator'
Assert-Check ($null -eq $metrics.modelSelectedPositiveOutcomePercent) 'Empty selection must have undefined precision'
Assert-Check ($metrics.warnings -contains 'INCOMPLETE_OUTCOME_LABELS') 'Missing labels not flagged'
Assert-Check ($metrics.warnings -contains 'ALL_VALID_DECISIONS_REJECTED') 'Reject-all not flagged'
$empty = Get-TypedDecisionEvaluation @()
Assert-Check ($null -eq $empty.modelPositiveOutcomeRecallPercent) 'No positives must have undefined recall'
Write-Progress -Activity 'Offline decision evaluation tests' -Completed
Write-Host '[100%] Offline decision evaluation checks passed.'
