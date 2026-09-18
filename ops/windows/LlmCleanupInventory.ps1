# Read-only collectors. Dot-sourcing defines functions only; no inventory or inference is run.
Set-StrictMode -Version Latest

function Get-LlmInventoryField($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Assert-LlmInventoryLoopback([string]$BaseUrl) {
    $uri = $null
    if (-not [uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'http' -or $uri.Host -notin @('localhost','127.0.0.1','[::1]','::1') -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') {
        throw 'Only a plain loopback HTTP base URL is allowed; no credentials, path, query or fragment.'
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}

function Get-LlmInventoryOllama([string]$BaseUrl, [int]$TimeoutSeconds = 10) {
    $base = Assert-LlmInventoryLoopback $BaseUrl
    foreach ($endpoint in @('tags','ps')) {
        try {
            # Documented read-only endpoints; no generate/chat/show/pull/delete request.
            $response = Invoke-RestMethod -Uri ($base + '/api/' + $endpoint) -Method Get -TimeoutSec $TimeoutSeconds -MaximumRedirection 0 -ErrorAction Stop
            $property = $response.PSObject.Properties['models']
            if ($null -eq $property -or $null -eq $property.Value -or $property.Value -isnot [array]) {
                throw 'Invalid model-list response.'
            }
            $models = @(foreach ($model in $property.Value) {
                $details = Get-LlmInventoryField $model 'details'
                [pscustomobject]@{
                    name = Get-LlmInventoryField $model 'name'
                    digest = Get-LlmInventoryField $model 'digest'
                    logicalSizeBytes = Get-LlmInventoryField $model 'size'
                    parameterSize = Get-LlmInventoryField $details 'parameter_size'
                    quantization = Get-LlmInventoryField $details 'quantization_level'
                    format = Get-LlmInventoryField $details 'format'
                    sizeVramBytes = Get-LlmInventoryField $model 'size_vram'
                    contextLength = Get-LlmInventoryField $model 'context_length'
                    expiresAt = Get-LlmInventoryField $model 'expires_at'
                }
            })
            [pscustomobject]@{ endpoint = '/api/' + $endpoint; status = 'AVAILABLE'; models = $models; errorType = $null }
        } catch {
            # Error messages/bodies can echo URLs or credentials. Export type only.
            [pscustomobject]@{ endpoint = '/api/' + $endpoint; status = 'UNKNOWN_UNAVAILABLE_OR_INVALID'; models = @(); errorType = $_.Exception.GetType().Name }
        }
    }
}

function Get-LlmInventoryFiles([string[]]$Roots, [int]$MaxEntries = 10000, [int]$MaxDepth = 10, [int]$MaxSeconds = 30) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $files = [Collections.Generic.List[object]]::new()
    $rootResults = [Collections.Generic.List[object]]::new()
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = 0
    $errors = 0
    $skippedLinks = 0
    $depthLimited = $false
    $limitReached = $false
    foreach ($root in ($Roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if ($limitReached) { $rootResults.Add([pscustomobject]@{path=$root;status='NOT_SCANNED_LIMIT'}); continue }
        try {
            if (-not [IO.Path]::IsPathRooted($root) -or $root.StartsWith('\\')) { throw 'Only absolute local model directories are supported.' }
            $full = [IO.Path]::GetFullPath($root).TrimEnd('\','/')
            $driveRoot = [IO.Path]::GetPathRoot($full).TrimEnd('\','/')
            if ($full -eq $driveRoot -or $full -eq $env:USERPROFILE -or $full -eq $env:LOCALAPPDATA -or $full -eq (Get-Location).Path) {
                throw 'Broad roots cannot be scanned.'
            }
            if (-not (Test-Path -LiteralPath $full)) { $rootResults.Add([pscustomobject]@{path=$full;status='MISSING'}); continue }
            $rootItem = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            if (-not $rootItem.PSIsContainer) { throw 'Model directory must be a directory.' }
            if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $skippedLinks++; $rootResults.Add([pscustomobject]@{path=$full;status='SKIPPED_REPARSE_ROOT'}); continue
            }
            $rootState = [pscustomobject]@{path=$full;status='SCANNED'}
            $rootResults.Add($rootState)
            $queue = [Collections.Generic.Queue[object]]::new()
            $queue.Enqueue([pscustomobject]@{path=$full;depth=0})
            while ($queue.Count -gt 0) {
                if ($entries -ge $MaxEntries -or $clock.Elapsed.TotalSeconds -ge $MaxSeconds) { $limitReached=$true; $rootState.status='PARTIAL_LIMIT'; break }
                $node = $queue.Dequeue()
                if (-not $visited.Add($node.path)) { continue }
                $enumerator = $null
                try {
                    # Lazy enumeration avoids materialising an entire cache. Directory links are never followed.
                    $enumerator = [IO.Directory]::EnumerateFileSystemEntries($node.path).GetEnumerator()
                    while ($enumerator.MoveNext()) {
                        if ($entries -ge $MaxEntries -or $clock.Elapsed.TotalSeconds -ge $MaxSeconds) { $limitReached=$true; $rootState.status='PARTIAL_LIMIT'; break }
                        $entries++
                        try {
                            $item = Get-Item -LiteralPath $enumerator.Current -Force -ErrorAction Stop
                            $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
                            if ($item.PSIsContainer) {
                                if ($isLink) { $skippedLinks++; continue }
                                if ($node.depth -ge $MaxDepth) { $depthLimited=$true; continue }
                                $queue.Enqueue([pscustomobject]@{path=$item.FullName;depth=$node.depth+1})
                            } elseif ($item.Extension -ieq '.gguf') {
                                $files.Add([pscustomobject]@{path=$item.FullName;logicalSizeBytes=$item.Length;modifiedAtUtc=$item.LastWriteTimeUtc.ToString('o');isReparsePoint=$isLink;sha256=$null})
                            }
                        } catch { $errors++ }
                    }
                } catch { $errors++; $rootState.status='PARTIAL_ACCESS_ERROR' }
                finally { if ($null -ne $enumerator -and $enumerator -is [IDisposable]) { $enumerator.Dispose() } }
                if ($limitReached) { break }
            }
        } catch { $errors++; $rootResults.Add([pscustomobject]@{path=$root;status='INVALID_OR_INACCESSIBLE'}) }
    }
    [pscustomobject]@{
        roots=$rootResults.ToArray(); files=$files.ToArray(); entriesInspected=$entries
        partial=($limitReached -or $depthLimited -or $errors -gt 0 -or $skippedLinks -gt 0)
        limitReached=$limitReached; depthLimited=$depthLimited; accessErrors=$errors; skippedDirectoryLinks=$skippedLinks
        elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,2)
        limitations='Known/explicit roots only. Files are not hashed or loaded. Logical sizes do not establish unique physical usage or recoverable space. No directory links followed; filesystem stalls can exceed the cooperative time budget.'
    }
}

function Get-LlmInventoryRuntime {
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('ollama.exe','llama-cli.exe','llama-server.exe')) {
        foreach ($command in @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue)) { [void]$paths.Add($command.Source) }
        $known = Join-Path 'C:\MarketBrainTools\llama.cpp' $name
        if (Test-Path -LiteralPath $known -PathType Leaf) { [void]$paths.Add($known) }
    }
    if ($env:LOCALAPPDATA) {
        $known = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
        if (Test-Path -LiteralPath $known -PathType Leaf) { [void]$paths.Add($known) }
    }
    $executables = @(foreach ($path in $paths) {
        try { $item=Get-Item -LiteralPath $path -ErrorAction Stop; [pscustomobject]@{path=$path;fileVersion=$item.VersionInfo.FileVersion;productVersion=$item.VersionInfo.ProductVersion} }
        catch { [pscustomobject]@{path=$path;fileVersion=$null;productVersion=$null} }
    })
    $processes = @(foreach ($process in @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match '^(ollama.*|llama-cli|llama-server)$' })) {
        $path=$null; $started=$null
        try {$path=$process.Path; $started=$process.StartTime.ToUniversalTime().ToString('o')} catch { }
        [pscustomobject]@{name=$process.ProcessName;id=$process.Id;path=$path;startedAtUtc=$started;workingSetBytes=$process.WorkingSet64}
    })
    [pscustomobject]@{executables=$executables;processes=$processes;limitations='File metadata only; binaries not executed. Empty process list does not establish no queued/Java/scheduled jobs. Nonstandard executable locations may be absent.'}
}

function Get-LlmInventoryHardware {
    $results = [ordered]@{}
    foreach ($kind in @('Memory','Cpu','Gpu','Disks')) {
        try {
            $data = switch ($kind) {
                'Memory' { Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop | Select-Object TotalVisibleMemorySize,FreePhysicalMemory }
                'Cpu' { Get-CimInstance Win32_Processor -OperationTimeoutSec 5 -ErrorAction Stop | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors }
                'Gpu' { Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 -ErrorAction Stop | Select-Object Name,AdapterRAM,DriverVersion }
                'Disks' { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 5 -ErrorAction Stop | Select-Object DeviceID,Size,FreeSpace }
            }
            $results[$kind]=[pscustomobject]@{status='COLLECTED';data=@($data)}
        } catch { $results[$kind]=[pscustomobject]@{status='UNKNOWN';data=@();errorType=$_.Exception.GetType().Name} }
    }
    [pscustomobject]@{sections=$results;limitations='Memory values are KiB; disk and AdapterRAM values are bytes. Win32_VideoController AdapterRAM can be missing/truncated/inaccurate, especially above 4 GiB; not authoritative free VRAM. No hardware serial numbers or usernames collected.'}
}

function Get-LlmInventoryReferences([string]$RepositoryDirectory) {
    $files = [Collections.Generic.List[object]]::new()
    foreach ($relative in @('compose.yaml','marketbrain-service/src/main/resources/application.yml')) { $files.Add([pscustomobject]@{path=(Join-Path $RepositoryDirectory $relative);relative=$relative}) }
    $ops = Join-Path $RepositoryDirectory 'ops/windows'
    if (Test-Path -LiteralPath $ops) {
        foreach ($file in @(Get-ChildItem -LiteralPath $ops -File -Filter '*.ps1' -ErrorAction Stop | Select-Object -First 200)) {
            $files.Add([pscustomobject]@{path=$file.FullName;relative='ops/windows/'+$file.Name})
        }
    }
    $references = @(foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file.path -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $file.path -ErrorAction Stop
        if ($item.Length -gt 1MB) { continue }
        $body = [IO.File]::ReadAllText($file.path)
        # Fixed tokens only: never emit whole config lines, environment values or file bodies.
        $tokens = @([regex]::Matches($body,'(?i)granite|qwen2\.5-0\.5b|qwen2\.5-1\.5b|gemma|qwen3|llama-cli|llama-server|MARKETBRAIN_OLLAMA_BASE_URL') | ForEach-Object {$_.Value.ToLowerInvariant()} | Sort-Object -Unique)
        if ($tokens.Count) { [pscustomobject]@{file=$file.relative;tokens=$tokens} }
    })
    [pscustomobject]@{references=$references;limitations='Hints from two tracked config paths and at most 200 top-level PowerShell files <=1 MiB; may include tests, not active dependencies. No .env, credentials, process arguments, Docker inspect or resolved config read. Runtime dependency/job verification remains pending.'}
}

function Save-LlmInventoryReport($Report, [string]$Path) {
    $Report.updatedAtUtc=[DateTime]::UtcNow.ToString('o')
    $json=$Report | ConvertTo-Json -Depth 16
    $temporary=$Path+'.pending-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($false))
    # Windows PowerShell 5.1 coerces $null to an empty string for this overload.
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary,$Path) }
}

function Invoke-LlmInventoryStage($Report,[string]$Name,[scriptblock]$Collector) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try { $Report.sections[$Name]=[pscustomobject]@{status='COLLECTED';data=(& $Collector)} }
    catch { $Report.sections[$Name]=[pscustomobject]@{status='UNKNOWN';errorType=$_.Exception.GetType().Name}; $Report.warnings.Add($Name+': collection unavailable; do not infer absence.') }
    finally { $timer.Stop(); $Report.timingsSeconds[$Name]=[math]::Round($timer.Elapsed.TotalSeconds,2) }
}
