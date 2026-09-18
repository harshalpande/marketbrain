# Definitions only. Never invoke inference, change jobs, or export raw command arguments.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')

function Get-LlmDependencyTokens([string]$Text) {
    @([regex]::Matches($Text,'(?i)marketbrain|ollama|llama-cli|llama-server|granite|qwen|typeddecision|typed-decision|powershell|pwsh|cmd\.exe') |
        ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
}

function Get-LlmDependencyTasks {
    # Read action metadata to match fixed tokens, but never put action text in evidence.
    $tasks=@(Get-CimInstance -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName MSFT_ScheduledTask -OperationTimeoutSec 10 -ErrorAction Stop | Select-Object -First 1001)
    $matches=@(foreach ($task in ($tasks | Select-Object -First 1000)) {
        $parts=[Collections.Generic.List[string]]::new()
        $parts.Add([string](Get-LlmInventoryField $task 'TaskName'))
        foreach ($action in @(Get-LlmInventoryField $task 'Actions')) {
            foreach ($field in @('Execute','Arguments','WorkingDirectory')) { $parts.Add([string](Get-LlmInventoryField $action $field)) }
        }
        $tokens=@(Get-LlmDependencyTokens ($parts -join ' '))
        if ($tokens.Count) {
            # Opaque index instead of task names/paths, which can also contain private data.
            $state=Get-LlmInventoryField $task 'State'
            [pscustomobject]@{taskIndex=[array]::IndexOf($tasks,$task);stateCode=if ([string]$state -match '^[0-4]$') {[int]$state} else {$null};tokens=$tokens}
        }
    })
    [pscustomobject]@{inspectedCount=[math]::Min(1000,$tasks.Count);partial=($tasks.Count -gt 1000);matches=$matches;limitations='Token hints only, including generic shell wrappers. Disabled tasks may still be future dependencies. Task bodies, accounts, names and arguments are not exported. Indirect wrappers may be missed; review locally before removal.'}
}

function Get-LlmDependencyProcesses {
    @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match '^(java|javaw|powershell|pwsh|ollama.*|llama-cli|llama-server)$' } |
        Select-Object @{n='name';e={$_.ProcessName}},Id,@{n='isCollectorProcess';e={$_.Id -eq $PID}})
}

function Get-LlmDependencyEvidence([string]$ReviewDirectory,[int]$MaxEntries=2000,[int]$MaxSeconds=20) {
    $root=[IO.Path]::GetFullPath($ReviewDirectory).TrimEnd('\','/')
    if (-not [IO.Path]::IsPathRooted($ReviewDirectory) -or $root.StartsWith('\\') -or
        $root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\','/') -or $root -eq $env:USERPROFILE -or $root -eq (Get-Location).Path) { throw 'Use a specific local review directory, not a broad root.' }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject]@{status='UNKNOWN_MISSING_DIRECTORY';records=@();partial=$true}
    }
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Review root cannot be a directory link.' }
    $queue=[Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{path=$root;depth=0})
    $records=[Collections.Generic.List[object]]::new()
    $timer=[Diagnostics.Stopwatch]::StartNew();$count=0;$partial=$false;$errors=0;$links=0
    while ($queue.Count -and $count -lt $MaxEntries -and $timer.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $node=$queue.Dequeue();$iterator=$null
        try {
            $iterator=[IO.Directory]::EnumerateFileSystemEntries($node.path).GetEnumerator()
            while ($iterator.MoveNext()) {
                if ($count -ge $MaxEntries -or $timer.Elapsed.TotalSeconds -ge $MaxSeconds) {$partial=$true;break}
                $count++
                try {
                    $item=Get-Item -LiteralPath $iterator.Current -Force -ErrorAction Stop
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {$links++;$partial=$true;continue}
                    if ($item.PSIsContainer) {
                        if ($node.depth -lt 3) {$queue.Enqueue([pscustomobject]@{path=$item.FullName;depth=$node.depth+1})} else {$partial=$true}
                        continue
                    }
                    if ($item.Name -notin @('status.json','sweep.json','comparison.json')) {continue}
                    if ($item.Length -gt 2MB) {$partial=$true;continue}
                    $json=[IO.File]::ReadAllText($item.FullName) | ConvertFrom-Json -ErrorAction Stop
                    $state=[string](Get-LlmInventoryField $json 'status')
                    $known=$state -in @('COMPLETED','FAILED','LOST_AFTER_RESTART','RUNNING','QUEUED','PENDING','INTERRUPTED','PAUSED_BUDGET','PAUSED_CALL_BUDGET','COMPLETED_SCREENING','COMPLETED_VALIDATION_REVIEW_REQUIRED','COMPLETED_REVIEW_REQUIRED','REVIEW_REQUIRED','REVIEW_WITH_WARNINGS','DIAGNOSTIC_GATE_BLOCKED','INCOMPARABLE_INPUTS')
                    $terminal=$state -in @('COMPLETED','FAILED','COMPLETED_SCREENING','COMPLETED_VALIDATION_REVIEW_REQUIRED','COMPLETED_REVIEW_REQUIRED','REVIEW_REQUIRED','REVIEW_WITH_WARNINGS','DIAGNOSTIC_GATE_BLOCKED','INCOMPARABLE_INPUTS')
                    $jobId=[guid]::Empty
                    $validId=[guid]::TryParse([string](Get-LlmInventoryField $json 'jobId'),[ref]$jobId)
                    $records.Add([pscustomobject]@{file=$item.FullName;modifiedAtUtc=$item.LastWriteTimeUtc.ToString('o');status=if($known){$state}else{'UNKNOWN'};jobId=if($validId){$jobId.ToString()}else{$null};requiresReview=(-not $terminal);modelTokens=@(Get-LlmDependencyTokens ([string](Get-LlmInventoryField $json 'model')))})
                } catch {$errors++;$partial=$true}
            }
        } catch {$errors++;$partial=$true}
        finally {if ($null -ne $iterator -and $iterator -is [IDisposable]) {$iterator.Dispose()}}
    }
    if ($queue.Count) {$partial=$true}
    [pscustomobject]@{status='COLLECTED';records=$records.ToArray();entriesInspected=$count;partial=$partial;accessOrParseErrors=$errors;skippedLinks=$links;limitations='Saved evidence only, not live worker state. May be stale or on a different/custom mount. Depth 3, entry/time/2 MiB file limits. Other job families and external schedulers are not covered. No job-status HTTP requests because the Java GET may rewrite recovered status.'}
}

function Get-LlmDependencyHealth([string]$BaseUrl) {
    $base=Assert-LlmInventoryLoopback $BaseUrl
    $response=Invoke-RestMethod -Uri ($base+'/actuator/health') -Method Get -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
    $status=[string](Get-LlmInventoryField $response 'status')
    [pscustomobject]@{status=if($status -in @('UP','DOWN','OUT_OF_SERVICE','UNKNOWN')){$status}else{'UNKNOWN'};limitations='Reachability only; not readiness, deployed revision or absence of active jobs.'}
}
