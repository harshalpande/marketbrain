#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName='New')]
param(
    [Parameter(Mandatory,ParameterSetName='New')][string]$SourceSweepPath,
    [Parameter(Mandatory,ParameterSetName='Resume')][string]$ResumeDirectory,
    [Parameter(ParameterSetName='New')][string]$OutputDirectory='C:\MarketBrainData\Review',
    [Parameter(ParameterSetName='New')][ValidateRange(30,300)][int]$TimeoutSeconds=120
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionDiagnostics.ps1')
$diagnosticClock=[Diagnostics.Stopwatch]::StartNew()
$report=$null;$runDirectory=$null;$lock=$null;$canSave=$false;$previousSeconds=0
function Save-DiagnosticProgress([string]$Message) {
    $report.updatedAt=[DateTime]::UtcNow.ToString('o')
    $report.elapsedSeconds=[math]::Round($previousSeconds+$diagnosticClock.Elapsed.TotalSeconds,2)
    $report.completed=$report.records.Count;$report.progressPercent=[int][math]::Floor(100*$report.completed/20)
    $report.detail=$Message;$report.summary=@(Get-DecisionDiagnosticSummary $report)
    Save-TypedDecisionEvidence $report (Join-Path $runDirectory 'diagnostics.json') -KeepBackup
    $line="[$($report.progressPercent)%] $($report.updatedAt) $Message; completed=$($report.completed)/20; elapsed=$($report.elapsedSeconds)s"
    [IO.File]::AppendAllText((Join-Path $runDirectory 'diagnostics.log'),$line+[Environment]::NewLine)
    Write-Host $line
    Write-Progress -Id 92 -Activity 'Decision communication diagnostics' -Status $Message -PercentComplete $report.progressPercent
}
try {
    $lock=[IO.File]::Open((Join-Path ([IO.Path]::GetTempPath()) 'marketbrain-typed-decision-sweep.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if (@(Get-Process -Name 'llama-cli','llama-server' -ErrorAction SilentlyContinue).Count) { throw 'Another llama process is active. Stop the other test before starting diagnostics.' }
    $identity=[ordered]@{}
    foreach ($file in @('RunTypedDecisionCommunicationDiagnostics.ps1','TypedDecisionDiagnostics.ps1','TypedDecisionEvaluation.ps1','TypedDecisionSweep.ps1')) {
        $identity[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file)).Hash
    }
    if ($ResumeDirectory) {
        $runDirectory=(Resolve-Path -LiteralPath $ResumeDirectory).Path
        $report=ConvertFrom-SweepJson (Get-Content -LiteralPath (Join-Path $runDirectory 'diagnostics.json') -Raw)
        if ($report.version -ne 'TYPED_COMMUNICATION_DIAGNOSTIC_V1' -or $report.codeHash -ne (Get-SweepHash $identity) -or
            $report.planHash -ne (Get-SweepHash $report.plan) -or (Get-SweepHash $report.arms) -ne (Get-SweepHash $report.plan.arms)) { throw 'Diagnostic code or frozen plan changed. Do not mix runs.' }
        $previousSeconds=$report.elapsedSeconds
    } else {
        $source=ConvertFrom-SweepJson (Get-Content -LiteralPath $SourceSweepPath -Raw)
        if ($source.version -ne 'TYPED_SWEEP_V1' -or $source.status -notin @('COMPLETED_NO_QUALIFIER','COMPLETED_SCREENING') -or
            $source.snapshotHash -ne (Get-SweepHash $source.snapshot) -or
            $source.snapshot.decisionContractVersion -ne 'MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5' -or
            $source.snapshot.selectionMode -ne 'CONTRAST_VALIDATION' -or $source.snapshot.candidates.Count -ne 4) { throw 'A completed V5 four-case contrast sweep is required.' }
        $candidates=@($source.snapshot.candidates)
        $symbols=@($candidates.symbol | Sort-Object)
        if (($symbols -join ',') -ne 'SYNTHETIC_HIGH_VOL,SYNTHETIC_MISSING_VOLUME,SYNTHETIC_STRONG,SYNTHETIC_WEAK' -or
            @($candidates.candidateId | Sort-Object -Unique).Count -ne 4) { throw 'Unexpected diagnostic case identities.' }
        $arms=@(Get-DecisionDiagnosticArms)
        # Pair each case across arms. No answer-based filtering, retries, or winning-config selection.
        $tasks=@(foreach ($c in $candidates) { foreach ($arm in $arms) {
            $input=New-DecisionDiagnosticInput $c $arm $source.snapshot.grammar
            [pscustomobject]@{id=($c.candidateId+'-'+$arm.id);candidateId=$c.candidateId;armId=$arm.id;prompt=$input.prompt;grammar=$input.grammar}
        }})
        $plan=[pscustomobject]@{modelPath=$source.settings.modelPath;modelSha256=$source.modelSha256
            executablePath=$source.settings.llamaCliPath;executableSha256=$source.llamaSha256
            modelRef=$source.settings.modelRef;timeoutSeconds=$TimeoutSeconds;contextSize=4096;maxTokens=160;temperature=0;seed=1729;maxInvocations=24
            sourceSweepSha256=(Get-FileHash -LiteralPath $SourceSweepPath).Hash;candidates=$candidates;tasks=$tasks;arms=$arms}
        $runDirectory=Join-Path $OutputDirectory ('typed-diagnostics-'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Path $runDirectory | Out-Null
        $runDirectory=(Resolve-Path -LiteralPath $runDirectory).Path
        $report=[pscustomobject]@{version='TYPED_COMMUNICATION_DIAGNOSTIC_V1';status='RUNNING';createdAt=[DateTime]::UtcNow.ToString('o');updatedAt=$null
            codeIdentity=$identity;codeHash=(Get-SweepHash $identity);plan=$plan;planHash=(Get-SweepHash $plan);arms=$arms
            ownerPid=$PID;ownerStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            completed=0;progressPercent=0;elapsedSeconds=0;detail='';activeTask=$null;help=$null;records=@();summary=@();errors=@();startedInvocationCount=0
            modelConcurrency=1;databaseWritesPerformed=$false;signalsCreated=0;ordersCreated=0;actionExecutionEnabled=$false
            runtimeEvidenceInterpretation='Full input echo verifies CLI file ingestion, not model attention or complete token processing. Inspect runtime artifacts/logs for effective template, token counts and context; absent telemetry remains unknown. Settings in plan are requested, not independently verified effective values.'
            interpretation='Controlled diagnosis, not training or market accuracy. One-field correctness is not full policy validity. No automatic promotion to production.'}
    }
    if ((Get-FileHash -LiteralPath $report.plan.modelPath).Hash -ne $report.plan.modelSha256 -or
        (Get-FileHash -LiteralPath $report.plan.executablePath).Hash -ne $report.plan.executableSha256) { throw 'Model or executable differs from frozen source. No inference started.' }
    $canSave=$true;$report.ownerPid=$PID;$report.ownerStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    $report.status='RUNNING';Save-DiagnosticProgress 'Starting/resuming; original sweep untouched; no Java requests'
    Write-Host "Evidence directory: $runDirectory"
    if ($null -eq $report.help) {
        $report.help=Invoke-DecisionDiagnosticProcess $report.plan.executablePath @('--help') 30 $null
        Save-DiagnosticProgress 'Captured installed CLI capabilities'
    }
    $helpText=$report.help.stdout+"`n"+$report.help.stderr
    if ($report.help.exitCode -ne 0 -or $report.help.timedOut) { throw 'CLI help failed.' }
    foreach ($flag in @('--single-turn','--grammar-file','--seed','--ctx-size','--no-escape','--offline','--perf','--log-verbosity','--log-prompts-dir','--output-file','--chat-template','--no-display-prompt')) {
        if (-not $helpText.Contains($flag)) { throw "Installed CLI is missing $flag. No guessed fallback invocation." }
    }
    if ($helpText -notmatch '\bchatml\b') { throw 'Installed CLI does not advertise ChatML.' }
    foreach ($task in $report.plan.tasks) {
        if (@($report.records | Where-Object taskId -eq $task.id).Count) { continue }
        $report.activeTask=$task.id;Save-DiagnosticProgress "Running $($task.id)"
        $taskDirectory=Join-Path (Join-Path $runDirectory '_work') $task.id
        New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
        $recordPath=Join-Path $taskDirectory 'record.json'
        if (Test-Path -LiteralPath $recordPath) {
            $record=ConvertFrom-SweepJson (Get-Content -LiteralPath $recordPath -Raw)
            if ($record.taskId -ne $task.id -or $record.planHash -ne $report.planHash) { throw 'Child checkpoint identity mismatch.' }
        } else {
            if ($report.startedInvocationCount -ge $report.plan.maxInvocations) { $report.status='PAUSED_INVOCATION_BUDGET';break }
            # A fresh invocation folder preserves artifacts of an interrupted call instead of overwriting them.
            $invocationDirectory=Join-Path $taskDirectory ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $invocationDirectory 'runtime') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $invocationDirectory 'prompt.txt'),$task.prompt,[Text.UTF8Encoding]::new($false))
            if ($null -ne $task.grammar) { [IO.File]::WriteAllText((Join-Path $invocationDirectory 'grammar.gbnf'),$task.grammar,[Text.UTF8Encoding]::new($false)) }
            $arm=@($report.arms | Where-Object id -eq $task.armId)[0]
            $candidate=@($report.plan.candidates | Where-Object candidateId -eq $task.candidateId)[0]
            $arguments=@(Get-DecisionDiagnosticArguments $arm $report.plan.modelPath $invocationDirectory)
            $record=[pscustomobject]@{taskId=$task.id;planHash=$report.planHash;armId=$arm.id;symbol=$candidate.symbol;candidateId=$candidate.candidateId
                startedAt=[DateTime]::UtcNow.ToString('o');completedAt=$null;prompt=$task.prompt;grammar=$task.grammar
                promptFileSha256=(Get-FileHash -LiteralPath (Join-Path $invocationDirectory 'prompt.txt')).Hash
                arguments=$arguments;process=$null;conversation='';runtimeArtifacts=@();runtimeEvidenceLines=@();assessment=$null;error=$null}
            $report.startedInvocationCount++
            Save-DiagnosticProgress "Starting invocation $($report.startedInvocationCount)/$($report.plan.maxInvocations): $($task.id)"
            try {
                $record.process=Invoke-DecisionDiagnosticProcess $report.plan.executablePath $arguments $report.plan.timeoutSeconds { Save-DiagnosticProgress "Model active: $($task.id)" }
                $conversationPath=Join-Path $invocationDirectory 'conversation.txt'
                if (Test-Path -LiteralPath $conversationPath) { $record.conversation=[IO.File]::ReadAllText($conversationPath) }
                $record.runtimeArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $invocationDirectory 'runtime') -File -Recurse | ForEach-Object {
                    [pscustomobject]@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash
                        text=$(if ($_.Length -le 1048576) { [IO.File]::ReadAllText($_.FullName) } else { $null });omittedForSize=($_.Length -gt 1048576)}
                })
                $record.runtimeEvidenceLines=@(($record.process.stdout+"`n"+$record.process.stderr) -split "`n" | Where-Object { $_ -match 'template|n_ctx|prompt eval|eval time|sampl|temperature|seed|truncat' })
                $record.assessment=Test-DecisionDiagnosticResponse $candidate $arm $task.prompt $record.conversation $record.process
            } catch { $record.error=[pscustomobject]@{message=$_.Exception.Message;stack=$_.ScriptStackTrace} }
            $record.completedAt=[DateTime]::UtcNow.ToString('o')
            Save-TypedDecisionEvidence $record $recordPath
        }
        $report.records+=@($record);$report.activeTask=$null
        $outcome=if ($null -ne $record.assessment) { "schema=$($record.assessment.schemaValid); decision=$($record.assessment.decision); correct=$($record.assessment.decisionCorrect)" } else { 'no assessed response; inspect error' }
        Save-DiagnosticProgress "Recorded $($task.id); $outcome"
    }
    if ($report.records.Count -eq 20) { $report.status='COMPLETED_DIAGNOSTIC_REVIEW_REQUIRED' }
    Save-DiagnosticProgress $report.status
    $report.summary | Format-Table armId,completed,schemaValidCount,decisionCorrectCount,fullDiagnosticPassedCount,inputEchoVerifiedCount,processFailureCount -AutoSize
} catch {
    $original=$_
    if ($canSave) {
        $report.status='INTERRUPTED';$report.errors+=@([pscustomobject]@{message=$original.Exception.Message;at=[DateTime]::UtcNow.ToString('o');stack=$original.ScriptStackTrace})
        try { Save-DiagnosticProgress "Stopped: $($original.Exception.Message)" } catch { Write-Warning 'Could not update diagnostic checkpoint. Preserve .bak, .tmp and _work files.' }
    }
    throw $original
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    Write-Progress -Id 92 -Activity 'Decision communication diagnostics' -Completed
    if ($runDirectory) { Write-Host "Share only: $runDirectory\diagnostics.json and $runDirectory\diagnostics.log" }
}
