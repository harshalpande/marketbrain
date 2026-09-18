# Diagnostic helpers only. No top-level inference or service access.
function Get-DecisionDiagnosticArms {
    @(
        [pscustomobject]@{id='SEVEN_GBNF_AUTO';fields=7;constrained=$true;template='AUTO'}
        [pscustomobject]@{id='SEVEN_FREE_AUTO';fields=7;constrained=$false;template='AUTO'}
        [pscustomobject]@{id='ONE_GBNF_AUTO';fields=1;constrained=$true;template='AUTO'}
        [pscustomobject]@{id='ONE_FREE_AUTO';fields=1;constrained=$false;template='AUTO'}
        [pscustomobject]@{id='SEVEN_GBNF_CHATML';fields=7;constrained=$true;template='chatml'}
    )
}

function New-DecisionDiagnosticInput($Candidate, $Arm, [string]$BaseGrammar) {
    $prompt=[string]$Candidate.independentPrompt
    if ($prompt -notmatch 'Policy=TYPED_POLICY_V3' -or $prompt.Length -gt 6000 -or
        $prompt -notmatch 'Assess the following input, independently of any Java baseline:') { throw 'Unexpected independent prompt contract.' }
    if ($prompt -match 'Java guardrail expectation|actualRank=|targetNetReturnPercent=|javaDecision=') { throw 'Expected-answer leakage in input prompt.' }
    $grammar=New-IndependentDecisionGrammar $Candidate $BaseGrammar
    if ($Arm.fields -eq 1) {
        $prompt=$prompt.Replace('Fields: candidateId, decision, riskBucket, trapDetected, scoreBand, confidenceBand, primaryReasonCode.',
            'Output exactly one JSON field: decision. All other policy fields below are internal checks, not output fields.')
        $prompt=$prompt.Replace('Return the seven fields only. Keep decision, risk and score consistent.',
            'Return only the decision JSON object. Do not output candidateId, risk, score, confidence, reason or explanation.')
        $grammar=@'
root ::= "{" ws "\"decision\"" ws ":" ws decision ws "}" ws
decision ::= "\"REJECT\"" | "\"WATCHLIST\"" | "\"SHORTLIST\"" | "\"TOP_PICK\""
ws ::= [ \t\n]*
'@
    }
    [pscustomobject]@{prompt=$prompt;grammar=$(if ($Arm.constrained) { $grammar } else { $null })}
}

function Get-DecisionDiagnosticArguments($Arm,[string]$ModelPath,[string]$TaskDirectory) {
    # All arms share sampling/context/logging. No grammar/schema option in the FREE arms.
    $values=@('-m',$ModelPath,'-f',(Join-Path $TaskDirectory 'prompt.txt'),'-n','160','--temp','0','--seed','1729',
        '--ctx-size','4096','--single-turn','--no-display-prompt','--no-escape','--offline','--perf',
        '--log-verbosity','3','--log-prompts-dir',(Join-Path $TaskDirectory 'runtime'),
        '--output-file',(Join-Path $TaskDirectory 'conversation.txt'))
    if ($Arm.constrained) { $values+=@('--grammar-file',(Join-Path $TaskDirectory 'grammar.gbnf')) }
    if ($Arm.template -ne 'AUTO') { $values+=@('--chat-template',$Arm.template) }
    return $values
}

function Invoke-DecisionDiagnosticProcess([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds,[scriptblock]$Heartbeat) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Executable;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.RedirectStandardInput=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach ($arg in $Arguments) { [void]$info.ArgumentList.Add($arg) }
    # Prevent environment-level grammar, server-base or sampling overrides. Never log credential values.
    $removed=@($info.Environment.Keys | Where-Object { $_ -like 'LLAMA_ARG_*' })
    foreach ($name in $removed) { [void]$info.Environment.Remove($name) }
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    $clock=[Diagnostics.Stopwatch]::StartNew();$started=$false
    try {
        $started=$process.Start();if (-not $started) { throw 'Could not start diagnostic process.' }
        $process.StandardInput.Close()
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        $nextHeartbeat=15
        while (-not $process.WaitForExit(500)) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
            if ($clock.Elapsed.TotalSeconds -ge $nextHeartbeat) { if ($Heartbeat) { & $Heartbeat };$nextHeartbeat+=15 }
        }
        $timedOut=-not $process.HasExited
        if ($timedOut) { $process.Kill($true);if (-not $process.WaitForExit(5000)) { throw 'Timed-out process did not exit after termination.' } }
        [pscustomobject]@{exitCode=$(if ($timedOut) {-999} else {$process.ExitCode});timedOut=$timedOut
            stdout=$out.GetAwaiter().GetResult();stderr=$err.GetAwaiter().GetResult();elapsedSeconds=$clock.Elapsed.TotalSeconds
            clearedEnvironmentNames=$removed}
    } finally {
        if ($started) { try { if (-not $process.HasExited) { $process.Kill($true);[void]$process.WaitForExit(5000) } } catch { } }
        $process.Dispose()
    }
}

function Test-DecisionDiagnosticResponse($Candidate,$Arm,[string]$Prompt,[string]$Conversation,$Process) {
    # b11022 --output-file includes full User/Assistant turns. Verify the exact input before stripping it.
    $normalized=$Conversation.Replace("`r`n","`n").TrimStart([char]0xfeff)
    $prefix="User:`n"+$Prompt.Replace("`r`n","`n").TrimEnd("`n")+"`n`nAssistant:`n"
    $echoVerified=$normalized.StartsWith($prefix,[StringComparison]::Ordinal)
    $answer=if ($echoVerified) { $normalized.Substring($prefix.Length) } else { '' }
    $failures=@();$schema=$false;$decision=$null;$full=$null
    if (-not $echoVerified) { $failures+='FULL_INPUT_ECHO_NOT_VERIFIED' }
    if ($Arm.fields -eq 7) {
        $full=Test-TypedDecisionResponse -Text $answer -Prompt '' -Candidate $Candidate -ExitCode $Process.exitCode -TimedOut $Process.timedOut
        $schema=$full.schemaValid
        if ($null -ne $full.decision) { $decision=$full.decision.decision }
        $failures+=@($full.failures)
    } else {
        # One-field contract is deliberately not passed off as seven-field business validity.
        # Exact full object match rejects duplicate/extra fields, prose, arrays and multiple answers.
        $match=[regex]::Match($answer,'\A\s*\{\s*"decision"\s*:\s*"(REJECT|WATCHLIST|SHORTLIST|TOP_PICK)"\s*\}\s*\z')
        $schema=$match.Success
        if ($schema) { $decision=$match.Groups[1].Value } else { $failures+='INVALID_ONE_FIELD_RESPONSE' }
        if ($Process.exitCode -ne 0) { $failures+='PROCESS_EXIT_'+$Process.exitCode }
        if ($Process.timedOut) { $failures+='PROCESS_TIMEOUT' }
    }
    $decisionCorrect=$echoVerified -and $schema -and $Process.exitCode -eq 0 -and -not $Process.timedOut -and
        @($Candidate.diagnosticExpectedDecisions) -ccontains $decision
    $jsonOnly=if ($Arm.fields -eq 1) { $schema } else { $null -ne $full.extraction.json -and $answer.Trim() -ceq $full.extraction.json.Trim() }
    [pscustomobject]@{inputEchoVerified=$echoVerified;answer=$answer;schemaValid=$schema;jsonOnly=$jsonOnly;decision=$decision
        decisionCorrect=$decisionCorrect;businessValid=$(if ($null -ne $full) {$full.businessValid} else {$null})
        fullDiagnosticPassed=$(if ($null -ne $full) {$full.diagnosticPassed} else {$null})
        failures=$failures;fullEvaluation=$full}
}

function Get-DecisionDiagnosticSummary($Report) {
    foreach ($arm in $Report.arms) {
        $rows=@($Report.records | Where-Object armId -eq $arm.id)
        $valid=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.schemaValid}).Count
        $correct=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.decisionCorrect}).Count
        $business=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.businessValid -eq $true}).Count
        $full=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.fullDiagnosticPassed -eq $true}).Count
        [pscustomobject]@{armId=$arm.id;completed=$rows.Count;planned=4;schemaValidCount=$valid;decisionCorrectCount=$correct
            decisionCorrectPercent=25*$correct;fullDiagnosticPassedCount=$(if ($arm.fields -eq 7) {$full} else {$null})
            businessValidCount=$(if ($arm.fields -eq 7) {$business} else {$null})
            inputEchoVerifiedCount=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.inputEchoVerified}).Count
            jsonOnlyCount=@($rows | Where-Object {$null -ne $_.assessment -and $_.assessment.jsonOnly}).Count
            processFailureCount=@($rows | Where-Object {$null -ne $_.error -or $null -eq $_.process -or $_.process.exitCode -ne 0 -or $_.process.timedOut}).Count
            meanProcessSeconds=$(if ($rows.Count) { ($rows.process | Measure-Object elapsedSeconds -Average).Average } else {$null})
            readyForProduction=$false}
    }
}
