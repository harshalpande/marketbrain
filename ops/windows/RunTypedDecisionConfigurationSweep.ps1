#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName='New')]
param(
    [Parameter(Mandatory,ParameterSetName='New')][string]$DatasetRunId,
    [Parameter(Mandatory,ParameterSetName='New')][string]$ModelPath,
    [Parameter(Mandatory,ParameterSetName='Resume')][string]$ResumeDirectory,
    [string]$ModelRef='Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M',
    [Parameter(ParameterSetName='New')][string]$FinalistsFromDirectory,
    [string]$LlamaCliPath='C:\MarketBrainTools\llama.cpp\llama-cli.exe',
    [ValidateSet('CONTRAST_VALIDATION','BALANCED_VALIDATION','FIXED_SYMBOL','RANDOM_VALIDATION','DIFFICULT_TRAPS','RECOVERY_OVEREXTENSION')][string]$SelectionMode='CONTRAST_VALIDATION',
    [ValidateRange(0,500)][int]$StartOffset=0,
    [ValidateRange(1,24)][int]$CandidateLimit=4,
    [ValidateSet(5,20,60)][int]$RankingHorizonSessions=20,
    [ValidateSet('POLICY_FIRST','FACTS_FIRST')][string[]]$Layouts=@('POLICY_FIRST','FACTS_FIRST'),
    [ValidateSet('NONE','CONSISTENCY')][string[]]$ExampleModes=@('NONE','CONSISTENCY'),
    [ValidateRange(0,1)][double[]]$Temperatures=@(0,0.2),
    [ValidateRange(32,512)][int[]]$TokenLimits=@(160),
    [ValidateRange(2,5)][int]$Repeats=2,
    [ValidateRange(1,2147483640)][int]$BaseSeed=1729,
    [ValidateRange(1,4096)][int]$MaxCalls=256,
    [ValidateRange(1,720)][int]$MaxRunMinutes=120,
    [ValidateRange(10,300)][int]$TimeoutSeconds=120,
    [ValidateRange(1,5)][int]$TopCount=3,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
. (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1')
$sweepClock=[Diagnostics.Stopwatch]::StartNew()
$report=$null; $lock=$null; $runDirectory=$null

function Save-SweepProgress([string]$Message) {
    $report.updatedAt=[DateTime]::UtcNow.ToString('o')
    $report.completedTaskCount=@($report.records).Count
    $report.progressPercent=[int][math]::Floor(100.0*$report.completedTaskCount/[math]::Max(1,$report.tasks.Count))
    $report.elapsedSeconds=[math]::Round($sweepPreviousElapsed+$sweepClock.Elapsed.TotalSeconds,2)
    $report.leaderboard=@(Get-SweepLeaderboard $report)
    $report.topConfigurations=@($report.leaderboard | Where-Object { $_.qualifiesForNextStage } | Select-Object -First $report.settings.topCount)
    $report.detail=$Message
    Save-TypedDecisionEvidence $report (Join-Path $runDirectory 'sweep.json')
    $line='[{0}%] {1} {2}; completed={3}/{4}; elapsed={5:N0}s' -f $report.progressPercent,$report.updatedAt,$Message,$report.completedTaskCount,$report.tasks.Count,$report.elapsedSeconds
    [IO.File]::AppendAllText((Join-Path $runDirectory 'sweep.log'),$line+[Environment]::NewLine)
    Write-Progress -Id 90 -Activity 'Typed decision configuration sweep' -Status $Message -PercentComplete $report.progressPercent
    Write-Host $line
}

try {
    # Same per-user lock for all sweeps even when output directories differ. Other legacy runners must be idle.
    $lockPath=Join-Path ([IO.Path]::GetTempPath()) 'marketbrain-typed-decision-sweep.lock'
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if (@(Get-Process -Name 'llama-cli','llama-server' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Another llama process is running. Stop the other evaluation before starting/resuming.' }
    $identity=[ordered]@{}
    foreach ($name in @('RunTypedDecisionConfigurationSweep.ps1','TypedDecisionSweep.ps1','PreviewPrototypeSwingTypedDecisionPrimitives.ps1','TypedDecisionEvaluation.ps1')) {
        $identity[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash
    }
    if ($ResumeDirectory) {
        $runDirectory=(Resolve-Path -LiteralPath $ResumeDirectory).Path
        $report=ConvertFrom-SweepJson (Get-Content -LiteralPath (Join-Path $runDirectory 'sweep.json') -Raw)
        if ($report.version -ne 'TYPED_SWEEP_V1' -or (Get-SweepHash $identity) -ne $report.codeHash) { throw 'Sweep code changed: start a new sweep, do not mix versions.' }
        if ((Get-SweepHash $report.snapshot) -ne $report.snapshotHash -or (Get-SweepHash $report.configurations) -ne $report.configurationHash -or
            (Get-SweepHash $report.tasks) -ne $report.taskHash -or (Get-SweepHash $report.settings) -ne $report.settingsHash) { throw 'Frozen sweep inputs were modified.' }
        $ModelPath=$report.settings.modelPath; $LlamaCliPath=$report.settings.llamaCliPath
    } else {
        $configs=@(New-SweepConfigurations $Layouts $ExampleModes $Temperatures $TokenLimits)
        $sourceHash=$null; $sourceModelHash=$null
        if ($FinalistsFromDirectory) {
            $sourceFile=Join-Path $FinalistsFromDirectory 'sweep.json'
            $screen=ConvertFrom-SweepJson (Get-Content -LiteralPath $sourceFile -Raw)
            if ($screen.version -ne 'TYPED_SWEEP_V1' -or $screen.status -ne 'COMPLETED_SCREENING' -or $screen.codeHash -ne (Get-SweepHash $identity)) { throw 'Finalist source must be a completed screening with the same code.' }
            $configs=@(Get-SweepLeaderboard $screen | Where-Object { $_.qualifiesForNextStage } | Select-Object -First $TopCount | ForEach-Object { $_.configuration })
            if ($configs.Count -eq 0) { throw 'No qualified configurations to validate.' }
            if ($SelectionMode -eq 'CONTRAST_VALIDATION') { throw 'Use another selection mode for finalist validation.' }
            $sourceHash=(Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
            $sourceModelHash=$screen.modelSha256
        }
        $planned=$configs.Count*$Repeats*$CandidateLimit
        if ($configs.Count -gt 64 -or $planned -gt $MaxCalls) { throw "Sweep budget exceeded: $($configs.Count) configurations, $planned calls. Narrow axes or explicitly increase MaxCalls." }
        if ($SelectionMode -eq 'CONTRAST_VALIDATION' -and ($CandidateLimit -ne 4 -or $StartOffset -ne 0)) { throw 'Contrast screening requires all four cases at offset zero.' }
        $ModelPath=(Resolve-Path -LiteralPath $ModelPath).Path
        $LlamaCliPath=(Resolve-Path -LiteralPath $LlamaCliPath).Path
        if ([IO.Path]::GetExtension($ModelPath) -ne '.gguf') { throw 'ModelPath must be the existing local GGUF file.' }
        if ($sourceModelHash -and (Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash -ne $sourceModelHash) { throw 'Finalist validation must use the screened model weights.' }
        Write-Progress -Id 90 -Activity 'Typed decision configuration sweep' -Status 'Freezing dataset and model identity' -PercentComplete 0
        Write-Host "[0%] Freezing inputs for $planned calls. One model call at a time; no automatic repair retries."
        $snapshot=Get-SweepSnapshot $BaseUrl $DatasetRunId $SelectionMode $StartOffset $CandidateLimit $RankingHorizonSessions
        if ($snapshot.decisionContractVersion -ne 'MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V5' -or $snapshot.candidates.Count -ne $CandidateLimit -or
            $snapshot.datasetRunId -ne $DatasetRunId -or $snapshot.selectionMode -ne $SelectionMode -or $snapshot.rankingHorizonSessions -ne $RankingHorizonSessions) { throw 'Unexpected snapshot identity/count/contract. V5 service required.' }
        $tasks=@(for ($repeat=1;$repeat -le $Repeats;$repeat++) {
            # Reverse order on alternating repetitions to reduce systematic warmup/order bias.
            $order=@($configs); if ($repeat % 2 -eq 0) { [array]::Reverse($order) }
            foreach ($config in $order) { for ($case=0;$case -lt $CandidateLimit;$case++) {
                [pscustomobject]@{id="$($config.id)-R$repeat-C$case";configurationId=$config.id;repeat=$repeat;caseIndex=$case;seed=($BaseSeed+$repeat-1)}
            }}
        })
        $runDirectory=Join-Path $OutputDirectory ('typed-sweep-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
        $settings=[pscustomobject]@{modelPath=$ModelPath;modelRef=$ModelRef;llamaCliPath=$LlamaCliPath;repeats=$Repeats;timeoutSeconds=$TimeoutSeconds;topCount=$TopCount;maxCalls=$MaxCalls}
        $report=[pscustomobject]@{
            version='TYPED_SWEEP_V1';status='RUNNING';createdAt=[DateTime]::UtcNow.ToString('o');updatedAt=$null
            ownerPid=$PID;ownerStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            modelConcurrency=1;modelSha256=(Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash
            llamaSha256=(Get-FileHash -LiteralPath $LlamaCliPath -Algorithm SHA256).Hash
            codeIdentity=$identity;codeHash=(Get-SweepHash $identity);snapshot=$snapshot;snapshotHash=(Get-SweepHash $snapshot)
            configurations=$configs;configurationHash=(Get-SweepHash $configs);tasks=$tasks;taskHash=(Get-SweepHash $tasks)
            settings=$settings;settingsHash=(Get-SweepHash $settings);records=@();leaderboard=@();topConfigurations=@()
            finalistSourceSha256=$sourceHash
            completedTaskCount=0;progressPercent=0;elapsedSeconds=0;activeTask=$null;detail=''
            startedInvocationCount=0
            interruptions=@();errors=@();actionExecutionEnabled=$false;databaseWritesPerformed=$false;ordersCreated=0;signalsCreated=0
            interpretation='Screening only, not training or investment accuracy. No winner is guaranteed. Repeated cases are not independent market samples. Qualifiers need unseen validation.'
        }
    }
    # Pin both local model weights and executable, including on resume.
    if ((Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash -ne $report.modelSha256 -or
        (Get-FileHash -LiteralPath $LlamaCliPath -Algorithm SHA256).Hash -ne $report.llamaSha256) { throw 'Model or llama executable changed. Start a new sweep.' }
    $sweepPreviousElapsed=[double]$report.elapsedSeconds
    $report.ownerPid=$PID; $report.ownerStartedAt=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    $report.status='RUNNING'
    Save-SweepProgress 'Sweep started/resumed'
    Write-Host "Evidence/status directory: $runDirectory"
    foreach ($task in $report.tasks) {
        if (@($report.records | Where-Object { $_.taskId -eq $task.id }).Count) { continue }
        if ($sweepClock.Elapsed.TotalMinutes -ge $MaxRunMinutes) { $report.status='PAUSED_BUDGET'; break }
        $config=@($report.configurations | Where-Object { $_.id -eq $task.configurationId })[0]
        $report.activeTask=$task
        Save-SweepProgress "Running $($task.id)"
        $taskDirectory=Join-Path (Join-Path $runDirectory '_work') $task.id
        New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
        $output=Join-Path $taskDirectory 'output'
        New-Item -ItemType Directory -Path $output -Force | Out-Null
        # A child checkpoint can survive a power loss before the sweep record was committed.
        $existing=@(Get-ChildItem -LiteralPath $output -Filter '*.json')
        $result=$null; $taskError=$null; $taskClock=[Diagnostics.Stopwatch]::StartNew()
        if ($existing.Count -gt 1) { throw "Ambiguous child evidence: $($task.id)" }
        if ($existing.Count -eq 1) { $result=ConvertFrom-SweepJson (Get-Content -LiteralPath $existing[0].FullName -Raw) }
        if ($null -eq $result -and $report.interruptions -notcontains $task.id -and (Test-Path -LiteralPath (Join-Path $taskDirectory 'started.json'))) {
            $report.interruptions += $task.id
            Save-SweepProgress "Interrupted call has no checkpoint; retrying only $($task.id)"
        }
        if ($null -eq $result) {
            if ($report.startedInvocationCount -ge $report.settings.maxCalls) { $report.status='PAUSED_CALL_BUDGET';break }
            $one=ConvertFrom-SweepJson ($report.snapshot | ConvertTo-Json -Depth 100)
            $candidate=$one.candidates[$task.caseIndex]
            $candidate.independentPrompt=New-SweepPrompt $candidate.independentPrompt $config
            $one.candidates=@($candidate);$one.candidateCount=1
            $snapshotPath=Join-Path $taskDirectory 'input.json'
            Save-TypedDecisionEvidence $one $snapshotPath
            Save-TypedDecisionEvidence @{taskId=$task.id;startedAt=[DateTime]::UtcNow.ToString('o')} (Join-Path $taskDirectory 'started.json')
            $report.startedInvocationCount++
            Save-SweepProgress "Starting invocation $($report.startedInvocationCount): $($task.id)"
            $parameters=@{DatasetRunId=$one.datasetRunId;SelectionMode=$one.selectionMode;CandidateLimit=1;RankingHorizonSessions=$one.rankingHorizonSessions
                ModelRef=$report.settings.modelRef;ModelPath=$ModelPath;LlamaCliPath=$LlamaCliPath;SnapshotPath=$snapshotPath;OutputDirectory=$output
                EvaluationMode='INDEPENDENT';Temperature=$config.temperature;Seed=$task.seed;MaxTokens=$config.maxTokens;TimeoutSeconds=$report.settings.timeoutSeconds
                Heartbeat={ Save-SweepProgress "Running $($task.id); model process active" }}
            try { Invoke-SweepCandidate $parameters }
            catch { $taskError=[pscustomobject]@{message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace} }
            $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json')
            if ($files.Count -eq 1) { $result=ConvertFrom-SweepJson (Get-Content -LiteralPath $files[0].FullName -Raw) }
        }
        $attempt=$null
        if ($null -ne $result -and @($result.attempts).Count -eq 1) { $attempt=$result.attempts[0] }
        if ($null -ne $result -and $result.status -eq 'FAILED' -and $null -eq $taskError) {
            $taskError=[pscustomobject]@{message='Recovered failed child run; inspect embedded result';type='CHILD_FAILED';stack=''}
        }
        if ($null -eq $attempt -and $null -eq $taskError) { $taskError=[pscustomobject]@{message='No completed candidate evidence';type='MISSING_EVIDENCE';stack=''} }
        $logs=@(Get-ChildItem -LiteralPath $output -Filter '*.log' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        if ($logs) { [IO.File]::AppendAllText((Join-Path $runDirectory 'sweep.log'),"`n--- $($task.id) ---`n"+$logs) }
        $report.records += [pscustomobject]@{taskId=$task.id;configurationId=$task.configurationId;repeat=$task.repeat;caseIndex=$task.caseIndex;seed=$task.seed
            completedAt=[DateTime]::UtcNow.ToString('o');elapsedSeconds=$taskClock.Elapsed.TotalSeconds;error=$taskError;attempt=$attempt;result=$result}
        $report.activeTask=$null
        Save-SweepProgress "Recorded $($task.id)"
    }
    if ($report.records.Count -eq $report.tasks.Count) {
        $report.status=if ($report.snapshot.selectionMode -ne 'CONTRAST_VALIDATION') { 'COMPLETED_VALIDATION_REVIEW_REQUIRED' }
            elseif (@(Get-SweepLeaderboard $report | Where-Object { $_.qualifiesForNextStage }).Count) { 'COMPLETED_SCREENING' } else { 'COMPLETED_NO_QUALIFIER' }
    }
    Save-SweepProgress $report.status
    $report.leaderboard | Select-Object configurationId,completed,planned,qualifiesForNextStage,diagnosticPassPercent,businessValidPercent,unsafePromotionCount,meanAttemptSeconds | Format-Table -AutoSize
}
catch {
    if ($null -ne $report -and $null -ne $runDirectory -and (Get-Variable sweepPreviousElapsed -ErrorAction SilentlyContinue)) {
        $report.status='INTERRUPTED';$report.errors += [pscustomobject]@{message=$_.Exception.Message;stack=$_.ScriptStackTrace;at=[DateTime]::UtcNow.ToString('o')}
        Save-SweepProgress "Stopped: $($_.Exception.Message)"
    }
    throw
}
finally {
    if ($null -ne $lock) { $lock.Dispose() }
    Write-Progress -Id 90 -Activity 'Typed decision configuration sweep' -Completed
    if ($runDirectory) { Write-Host "Share only: $runDirectory\sweep.json and $runDirectory\sweep.log" }
}
