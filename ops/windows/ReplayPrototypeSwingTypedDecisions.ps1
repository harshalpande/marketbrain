[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
$sourceFile=Get-Item -LiteralPath $EvidencePath
if ($sourceFile.Length -gt 52428800) { throw 'Evidence exceeds the 50 MB replay limit.' }
$sourceHash=(Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
$source=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($sourceFile.FullName))
$runs=@(if ($source.PSObject.Properties['results']) { $source.results } else { $source })
if ($runs.Count -eq 0) { throw 'No completed or partial result runs found.' }
$count=0
foreach ($run in $runs) { $count += @($run.attempts).Count }
if ($count -eq 0) { throw 'No saved attempts to replay.' }
$directory=Join-Path $OutputDirectory ('typed-replay-' + (Get-Date -Format yyyyMMdd-HHmmss) + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $directory | Out-Null
$resultPath=Join-Path $directory 'replay.json'
$logPath=Join-Path $directory 'replay.log'
$report=[pscustomobject]@{
    status='RUNNING'; replayVersion='TYPED_REPLAY_V1'; sourcePath=$sourceFile.FullName; sourceSha256=$sourceHash
    evaluatorSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1') -Algorithm SHA256).Hash
    replayedAt=(Get-Date -Format o); originalEvidencePreserved=$true
    modelCallsPerformed=0; databaseWritesPerformed=$false; actionExecutionEnabled=$false
    interpretation='Re-evaluation of saved responses with saved candidate rules; not new inference or evidence of improved model intelligence.'
    results=@(); error=$null
}
$done=0
Start-Transcript -Path $logPath | Out-Null
try {
    Save-TypedDecisionEvidence $report $resultPath
    foreach ($run in $runs) {
        $result=[pscustomobject]@{modelRef=$run.modelRef; selectionMode=$run.selectionMode; attempts=@(); evaluation=$null; schemaValidPercent=$null; businessValidPercent=$null}
        $report.results += $result
        foreach ($old in $run.attempts) {
            $percent=[int][Math]::Floor(100.0*$done/$count)
            Write-Progress -Activity 'Offline typed decision replay' -Status "$done/$count responses" -PercentComplete $percent
            Write-Host "[$percent%] Replaying $($old.symbol); no model call."
            foreach ($required in @('stdout','prompt','offlineCandidateEvidence','llamaExitCode','llamaTimedOut','evaluationMode')) {
                if (-not $old.PSObject.Properties[$required] -or $null -eq $old.$required) { throw "Missing replay evidence: $required" }
            }
            $assessment=Test-TypedDecisionResponse -Text $old.stdout -Prompt $old.prompt -Candidate $old.offlineCandidateEvidence -ExitCode $old.llamaExitCode -TimedOut $old.llamaTimedOut -EvaluationMode $old.evaluationMode
            $row=ConvertFrom-Json -InputObject ($old | ConvertTo-Json -Depth 100)
            $row | Add-Member originalReported ([pscustomobject]@{schemaValid=$old.schemaValid; businessValid=$old.businessValid; failures=$old.failures}) -Force
            $updates=@{
                parseableJson=$assessment.parseableJson; schemaValid=$assessment.schemaValid; businessValid=$assessment.businessValid
                decisionAlignedWithJavaGuardrail=$assessment.aligned; failures=$assessment.failures; warnings=$assessment.warnings
                extraction=$assessment.extraction; responseJson=$assessment.extraction.json
                failureStage=$assessment.failureStage
                reasonEvidenceWarnings=$assessment.reasonEvidenceWarnings; diagnosticPassed=$assessment.diagnosticPassed
                diagnosticFailures=$assessment.diagnosticFailures; diagnosticExpectedDecisions=$assessment.diagnosticExpectedDecisions
            }
            $fieldMap=@{modelDecision='decision'; modelRiskBucket='riskBucket'; modelTrapDetected='trapDetected'; modelScoreBand='scoreBand'; modelConfidenceBand='confidenceBand'; modelPrimaryReasonCode='primaryReasonCode'}
            foreach ($name in $fieldMap.Keys) {
                $updates[$name]=if ($null -ne $assessment.decision) { $assessment.decision.($fieldMap[$name]) } else { $null }
            }
            foreach ($name in $updates.Keys) { $row | Add-Member -NotePropertyName $name -NotePropertyValue $updates[$name] -Force }
            $result.attempts += $row
            $done++
            Save-TypedDecisionEvidence $report $resultPath
        }
        $result.evaluation=Get-TypedDecisionEvaluation $result.attempts
        $result.schemaValidPercent=[Math]::Round(100.0*@($result.attempts | Where-Object schemaValid).Count/$result.attempts.Count,2)
        $result.businessValidPercent=[Math]::Round(100.0*@($result.attempts | Where-Object businessValid).Count/$result.attempts.Count,2)
    }
    $report.status='REPLAY_COMPLETE_REVIEW_REQUIRED'
    Save-TypedDecisionEvidence $report $resultPath
    Write-Host '[100%] Replay complete; original files unchanged.'
    $report.results | Select-Object modelRef,selectionMode,schemaValidPercent,businessValidPercent | Format-Table -AutoSize
}
catch {
    $report.status='FAILED'; $report.error=[pscustomobject]@{message=$_.Exception.Message; stack=$_.ScriptStackTrace}
    Save-TypedDecisionEvidence $report $resultPath
    throw
}
finally {
    Write-Progress -Activity 'Offline typed decision replay' -Completed
    Write-Host "Share: $resultPath"
    Write-Host "Share: $logPath"
    Stop-Transcript | Out-Null
}
