# Offline Windows filesystem regressions. No inference, HTTP, database or service calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
function Assert-Persistence([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$directory=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-evidence-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$checkpoint=Join-Path $directory 'checkpoint.json'
$held=$null
try {
    Write-Host '[10%] Checking initial creation, repeated replacement and previous-version backup...'
    foreach ($i in 0..40) {
        Save-TypedDecisionEvidence @{sequence=$i;payload=('evidence '+$i)} $checkpoint -KeepBackup
        Assert-Persistence ((Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json).sequence -eq $i) 'Checkpoint contents incorrect.'
        if ($i -gt 0) { Assert-Persistence ((Get-Content -LiteralPath ($checkpoint+'.bak') -Raw | ConvertFrom-Json).sequence -eq ($i-1)) 'Backup not previous committed version.' }
    }
    Assert-Persistence (@(Get-ChildItem -LiteralPath $directory -Filter '*.tmp').Count -eq 0) 'Successful saves left pending temp files.'
    Write-Host '[40%] Checking short-lived reader lock and bounded retry...'
    if (-not ('MarketBrainEvidenceTestLock' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public static class MarketBrainEvidenceTestLock {
    public static Thread Hold(string path, int milliseconds) {
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var thread = new Thread(() => { Thread.Sleep(milliseconds); stream.Dispose(); });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }
}
'@
    }
    $reader=[MarketBrainEvidenceTestLock]::Hold($checkpoint,700)
    Save-TypedDecisionEvidence @{sequence=41} $checkpoint -KeepBackup -WarningVariable retryWarnings
    $reader.Join()
    Assert-Persistence (@($retryWarnings).Count -gt 0) 'Transient lock did not exercise retry.'
    Assert-Persistence ((Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json).sequence -eq 41) 'Retry did not commit.'
    Write-Host '[65%] Checking exhausted retry preserves last committed and pending evidence...'
    $held=[IO.File]::Open($checkpoint,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $failed=$false
    try { Save-TypedDecisionEvidence @{sequence=42} $checkpoint -KeepBackup }
    catch { $failed=$_.Exception.Message -like '*after 6 replacement attempt(s)*' }
    finally { $held.Dispose();$held=$null }
    Assert-Persistence $failed 'Persistent lock did not stop after bounded attempts.'
    Assert-Persistence ((Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json).sequence -eq 41) 'Failed save damaged last checkpoint.'
    $pending=@(Get-ChildItem -LiteralPath $directory -Filter '*.tmp')
    Assert-Persistence ($pending.Count -eq 1) 'Failed save did not retain pending evidence.'
    Assert-Persistence ((Get-Content -LiteralPath $pending[0].FullName -Raw | ConvertFrom-Json).sequence -eq 42) 'Pending evidence incomplete.'
    Save-TypedDecisionEvidence @{sequence=43} $checkpoint -KeepBackup
    Assert-Persistence ((Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json).sequence -eq 43) 'Stale temp file prevented a later save.'
    Push-Location -LiteralPath $directory
    try {
        Save-TypedDecisionEvidence @{sequence=1} '.\relative.json'
        Save-TypedDecisionEvidence @{sequence=2} '.\relative.json'
        Assert-Persistence ((Get-Content -LiteralPath (Join-Path $directory 'relative.json') -Raw | ConvertFrom-Json).sequence -eq 2) 'Relative path ignored PowerShell working directory.'
        Assert-Persistence (-not (Test-Path -LiteralPath (Join-Path $directory 'relative.json.bak'))) 'Compact report unexpectedly added a backup.'
    } finally { Pop-Location }
    Write-Host '[100%] Persistence regressions passed; no model invoked.'
} finally {
    if ($null -ne $held) { $held.Dispose() }
    $resolved=[IO.Path]::GetFullPath($directory)
    if ((Split-Path -Parent $resolved) -eq ([IO.Path]::GetTempPath().TrimEnd('\')) -and (Split-Path -Leaf $resolved) -like 'marketbrain-evidence-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
