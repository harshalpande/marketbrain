# Offline regression tests; imports only pure functions. No HTTP, database or model calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
function Assert-Response([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
Write-Progress -Activity 'Typed response regression tests' -Status 'Captured console outputs' -PercentComplete 10
Write-Host '[10%] Replaying four captured production-format stdout responses...'
$fixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-fixtures/typed-decision-v4-echo-regression.json') -Raw | ConvertFrom-Json
$assessments=@(foreach ($a in $fixture.attempts) {
    Test-TypedDecisionResponse -Text $a.stdout -Prompt $a.prompt -Candidate $a.offlineCandidateEvidence -ExitCode $a.llamaExitCode -TimedOut $a.llamaTimedOut
})
Assert-Response (@($assessments | Where-Object schemaValid).Count -eq 4) 'Saved JSON not recovered'
Assert-Response (@($assessments | Where-Object businessValid).Count -eq 1) 'Semantic failures were hidden'
Assert-Response (@($assessments | Where-Object diagnosticPassed).Count -eq 0) 'Historical failures turned into artificial success'
Assert-Response (@($assessments | Where-Object { $_.extraction.echoRemoved }).Count -eq 4) 'Echo not isolated'
$candidate=$fixture.attempts[0].offlineCandidateEvidence
$json='{"candidateId":"CANDIDATE_001","decision":"SHORTLIST","riskBucket":"MEDIUM","trapDetected":"NO","scoreBand":"HIGH","confidenceBand":"MEDIUM","primaryReasonCode":"STRONG_MOMENTUM"}'
function Assess([string]$Text,[string]$Prompt='Test evidence',[int]$ExitCode=0,[bool]$TimedOut=$false) {
    Test-TypedDecisionResponse $Text $Prompt $candidate $ExitCode $TimedOut
}
Write-Progress -Activity 'Typed response regression tests' -Status 'Framing and invalid contracts' -PercentComplete 50
Write-Host '[50%] Checking echo-only, multiple objects, duplicate keys, truncated output and transport errors...'
Assert-Response ((Assess $json).businessValid) 'Plain JSON failed'
Assert-Response ((Assess ("Loading model...`n> Test evidence`n"+$json+"`n[ Prompt: 1 t/s ]")).businessValid) 'Full echo failed'
$prompt='Example answer ' + $json + ' is only an example.'
$echoOnly=Assess ("> " + $prompt) $prompt
Assert-Response (-not $echoOnly.parseableJson) 'Prompt example was accepted as model answer'
Assert-Response ((Assess ("> " + $prompt + "`n" + $json) $prompt).businessValid) 'Prompt example contaminated actual answer'
Assert-Response ((Assess ("> Unexpected prompt`n"+$json)).failures -contains 'UNRECOGNIZED_PROMPT_ECHO') 'Unknown prompt echo accepted'
Assert-Response ((Assess ($json+"`n"+$json)).failures -contains 'AMBIGUOUS_JSON_OBJECTS') 'Duplicate answers not rejected'
Assert-Response ((Assess $json.Replace('CANDIDATE_001','CANDIDATE_002')).schemaValid -eq $false) 'Wrong candidate accepted'
Assert-Response ((Assess $json.Replace('"decision":"SHORTLIST"','"decision":"REJECT","decision":"SHORTLIST"')).failures -contains 'DUPLICATE_KEY_decision') 'Duplicate field not rejected'
Assert-Response (-not (Assess $json.Substring(0,$json.Length-1)).schemaValid) 'Incomplete answer accepted'
Assert-Response (-not (Assess $json.Replace('"HIGH"','42')).schemaValid) 'Numeric enum accepted'
Assert-Response (-not (Assess $json.Replace('"SHORTLIST"','"shortlist"')).schemaValid) 'Wrong enum case accepted'
Assert-Response (-not (Assess ('{"wrapper":'+$json+'}')).schemaValid) 'Nested answer accepted'
Assert-Response (-not (Assess ('['+$json+']')).schemaValid) 'Array accepted as response object'
Assert-Response ((Assess ("log with unmatched {`n"+$json)).schemaValid) 'Stray brace hid answer'
Assert-Response ((Assess ('```json'+"`n"+$json+"`n"+'```')).schemaValid) 'Fenced JSON failed'
Assert-Response ((Assess $json 'Test evidence' 1).schemaValid -and -not (Assess $json 'Test evidence' 1).businessValid) 'Exit error polluted schema or was accepted'
Assert-Response (-not (Assess $json 'Test evidence' 0 $true).businessValid) 'Timed-out answer accepted'
Assert-Response ((Get-TypedResponseObject ('x'*1048577) '').error -eq 'RESPONSE_TOO_LARGE') 'Input bound missing'
$escapedJson='{"note":"escaped quote: \" and slash: \\\\ and braces: { }"}'
Assert-Response ((Get-TypedResponseObject $escapedJson '').json -ceq $escapedJson) 'Escaped strings confused brace scanner'
Write-Progress -Activity 'Typed response regression tests' -Completed
Write-Host '[100%] Captured-output and adversarial parser checks passed; zero model calls.'
