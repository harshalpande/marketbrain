# Definitions only. The entrypoint requires explicit interactive authorization before applying.
. (Join-Path $PSScriptRoot 'LlmDependencyReview.ps1')

function Assert-CleanupPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\')) {throw 'Cleanup paths must be absolute local paths.'}
    $full=[IO.Path]::GetFullPath($Path)
    if ($full.TrimEnd('\') -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) {throw 'A drive root is not a cleanup target.'}
    # Inspect every existing ancestor as Resolve-Path alone does not reject directory junctions.
    $cursor=$full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Linked cleanup paths are unsupported; review manually.'}
        }
        $parent=Split-Path -Parent $cursor
        if ($parent -eq $cursor) {break};$cursor=$parent
    }
    return $full
}

function Get-ApprovedCleanupPlan([string]$ProfileDirectory,[string]$RunId) {
    if ($RunId -notmatch '^llm-cleanup-\d{8}-\d{6}-[a-f0-9]{12}$') {throw 'Invalid run identifier.'}
    $hub=Join-Path $ProfileDirectory '.cache\huggingface\hub'
    [pscustomobject]@{
        granite='ibm/granite4.1:8b'
        graniteDigest='444af1c4b2fedd6b54041aca558e7300b0b3d5c0468c44619126240323ba2852'
        oldFile=Assert-CleanupPath (Join-Path $hub 'models--Qwen--Qwen2.5-0.5B-Instruct-GGUF\snapshots\9217f5db79a29953eb74d5343926648285ec7e67\qwen2.5-0.5b-instruct-q4_k_m.gguf')
        retainedFile=Assert-CleanupPath (Join-Path $hub 'models--Qwen--Qwen2.5-1.5B-Instruct-GGUF\snapshots\91cad51170dc346986eccefdc2dd33a9da36ead9\qwen2.5-1.5b-instruct-q4_k_m.gguf')
        quarantineFile=Assert-CleanupPath (Join-Path 'C:\MarketBrainData\ModelQuarantine' ($RunId+'\qwen2.5-0.5b-instruct-q4_k_m.gguf'))
        oldExpectedBytes=491400032;retainedExpectedBytes=1117320736
    }
}

function Get-CleanupSnapshot {
    $models=@(Get-LlmInventoryOllama 'http://127.0.0.1:11434' 10)
    foreach ($list in $models) {if ($list.status -ne 'AVAILABLE') {throw 'Ollama list unavailable; cleanup blocked.'}}
    if ($models.Count -ne 2) {throw 'Incomplete Ollama inventory; cleanup blocked.'}
    foreach ($list in $models) {foreach ($model in @($list.models)) {
        if ([string]::IsNullOrWhiteSpace($model.name) -or [string]::IsNullOrWhiteSpace($model.digest)) {throw 'Malformed Ollama model identity; cleanup blocked.'}
    }}
    if (@($models | Where-Object endpoint -eq '/api/ps')[0].models.Count -gt 0) {throw 'A model is loaded; leave jobs alone and retry only when idle.'}
    $active=@(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -in @('llama-cli','llama-server')})
    if ($active.Count) {throw 'llama.cpp process exists; cleanup blocked. Nothing will be stopped automatically.'}
    $health=Get-LlmDependencyHealth 'http://127.0.0.1:8080'
    if ($health.status -ne 'UP') {throw 'MarketBrain health is not UP; cleanup blocked.'}
    [pscustomobject]@{models=@($models | Where-Object endpoint -eq '/api/tags')[0].models;health=$health.status;capturedAtUtc=[DateTime]::UtcNow.ToString('o');cDriveFreeBytes=([IO.DriveInfo]::new('C:\')).AvailableFreeSpace}
}

function Assert-GraniteIdentity($Snapshot,$Plan) {
    $matches=@($Snapshot.models | Where-Object {$_.name -eq $Plan.granite})
    if ($matches.Count -gt 1 -or ($matches.Count -eq 1 -and $matches[0].digest -ne $Plan.graniteDigest)) {throw 'Granite identity changed since reviewed inventory; refusing deletion.'}
    return ($matches.Count -eq 1)
}

function Get-CleanupFileEvidence([string]$Path,[long]$ExpectedBytes) {
    $full=Assert-CleanupPath $Path
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -ne $ExpectedBytes) {throw 'Model file differs from approved path/size; review required.'}
    [pscustomobject]@{path=$full;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash}
}

function Move-ApprovedQwenFile($Plan,$Evidence) {
    $source=Assert-CleanupPath $Plan.oldFile
    $target=Assert-CleanupPath $Plan.quarantineFile
    if ([IO.Path]::GetPathRoot($source) -ne [IO.Path]::GetPathRoot($target)) {throw 'Quarantine must stay on the same volume.'}
    if (Test-Path -LiteralPath $target) {throw 'Quarantine destination already exists; refusing overwrite.'}
    $fresh=Get-CleanupFileEvidence $source $Plan.oldExpectedBytes
    if ($fresh.sha256 -ne $Evidence.sha256) {throw 'Qwen 0.5B changed after preflight.'}
    $parent=Split-Path -Parent $target
    [void](New-Item -ItemType Directory -Path $parent -Force)
    [void](Assert-CleanupPath $target)
    # Move exactly one validated file, never a directory or shared blob/cache root.
    [IO.File]::Move($source,$target)
    $after=Get-CleanupFileEvidence $target $Plan.oldExpectedBytes
    if ($after.sha256 -ne $Evidence.sha256 -or (Test-Path -LiteralPath $source)) {throw 'Quarantine verification failed; inspect recorded paths.'}
}

function Remove-ApprovedGranite {
    # Official Ollama deletion API; do not touch its blob store or uninstall the runtime.
    Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/delete' -Method Delete -ContentType 'application/json' -Body '{"model":"ibm/granite4.1:8b"}' -TimeoutSec 120 -MaximumRedirection 0 -ErrorAction Stop | Out-Null
}

function Invoke-ApprovedCleanup($Plan,$Report,[scriptblock]$Checkpoint,[bool]$Apply,[bool]$OperatorConfirmed) {
    if ($Apply -and -not $OperatorConfirmed) {throw 'Operator idle/dependency/removal confirmation is required.'}
    $Report.before=Get-CleanupSnapshot
    $present=Assert-GraniteIdentity $Report.before $Plan
    $Report.retainedBefore=Get-CleanupFileEvidence $Plan.retainedFile $Plan.retainedExpectedBytes
    if (Test-Path -LiteralPath $Plan.quarantineFile) {throw 'Quarantine destination exists; review required.'}
    foreach ($binary in @('C:\MarketBrainTools\llama.cpp\llama-cli.exe','C:\MarketBrainTools\llama.cpp\llama-server.exe')) {
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {throw 'Required retained llama.cpp executable missing.'}
    }
    if (Test-Path -LiteralPath $Plan.oldFile) {$Report.oldFileBefore=Get-CleanupFileEvidence $Plan.oldFile $Plan.oldExpectedBytes}
    & $Checkpoint 25 'Preflight passed; retained model hashed, loaded-model/process checks passed.'
    if (-not $Apply) {$Report.status='PREVIEW_ONLY'; & $Checkpoint 100 'Preview only; no models changed.'; return}
    # Recheck just before mutations. Operator must prevent new model requests during the window.
    $present=Assert-GraniteIdentity (Get-CleanupSnapshot) $Plan
    if ($null -ne $Report.oldFileBefore) {
        $Report.quarantineState='INTENT_RECORDED'
        & $Checkpoint 40 'Saving exact Qwen quarantine/restore paths before moving.'
        Move-ApprovedQwenFile $Plan $Report.oldFileBefore
        $Report.quarantineState='VERIFIED'
    } else {$Report.quarantineState='SOURCE_ALREADY_ABSENT_NOT_REMOVED_BY_THIS_RUN'}
    & $Checkpoint 55 'Qwen quarantine step complete; data/evidence/cache directories preserved.'
    $present=Assert-GraniteIdentity (Get-CleanupSnapshot) $Plan
    if ($present) {
        $Report.graniteState='DELETE_REQUEST_INTENT_RECORDED'
        & $Checkpoint 65 'Saving deletion intent for the exact reviewed Granite digest.'
        Remove-ApprovedGranite
        $Report.graniteState='DELETE_ACKNOWLEDGED'
    } else {$Report.graniteState='ALREADY_ABSENT_NOT_REMOVED_BY_THIS_RUN'}
    & $Checkpoint 80 'Checking retained model, Ollama list and service health.'
    $Report.after=Get-CleanupSnapshot
    if (Assert-GraniteIdentity $Report.after $Plan) {throw 'Granite still installed after deletion request.'}
    foreach ($model in @($Report.before.models | Where-Object {$_.name -ne $Plan.granite})) {
        if (@($Report.after.models | Where-Object {$_.name -eq $model.name -and $_.digest -eq $model.digest}).Count -ne 1) {throw 'Another model changed; review required.'}
    }
    $Report.retainedAfter=Get-CleanupFileEvidence $Plan.retainedFile $Plan.retainedExpectedBytes
    if ($Report.retainedAfter.sha256 -ne $Report.retainedBefore.sha256) {throw 'Retained Qwen 1.5B hash changed; review required.'}
    if (Test-Path -LiteralPath $Plan.oldFile) {throw 'Old Qwen path exists after cleanup; review possible concurrent download.'}
    $Report.observedCDriveFreeDeltaBytes=$Report.after.cDriveFreeBytes-$Report.before.cDriveFreeBytes
    $Report.status='COMPLETED_SCOPED_CLEANUP_REVIEW_REQUIRED'
    & $Checkpoint 100 'Scoped cleanup verified; Qwen 1.5B retained. No inference or live-job proof claimed.'
}
