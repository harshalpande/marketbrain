# Compatible with Windows PowerShell 5.1. Definitions only; no automatic elevation.
function Resolve-PaytmOperationsPowerShell {
    $candidate = if ($PSVersionTable.PSVersion.Major -ge 7) {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        $command = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $command.Source }
    }
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'OPS_POWERSHELL_7_NOT_FOUND: Install PowerShell 7 or run this launcher from your existing PowerShell 7 window.'
    }
    $file = Get-Item -LiteralPath $candidate
    if ($file.VersionInfo.FileMajorPart -lt 7) { throw 'OPS_POWERSHELL_7_REQUIRED' }
    return $file.FullName
}

function New-PaytmOperationsElevatedCommand {
    param([string]$Runner, [string]$Evidence, [string]$OutputDirectory)
    # Literal quoting, then UTF-16LE encoding: spaces/apostrophes cannot become commands.
    $runnerLiteral = $Runner.Replace("'", "''")
    $evidenceLiteral = $Evidence.Replace("'", "''")
    $outputLiteral = $OutputDirectory.Replace("'", "''")
    return @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'Continue'
Write-Host 'CONTINUE IN THIS NEW ADMINISTRATOR WINDOW. The original window only launched this one.'
try {
    & '$runnerLiteral' -OperationsEvidencePath '$evidenceLiteral' -OutputDirectory '$outputLiteral'
} catch {
    Write-Host ('Review stopped: ' + `$_.Exception.Message) -ForegroundColor Red
    Write-Host 'Share the JSON path printed above, if present. Do not repeat automatically.'
}
Write-Host 'This window stays open. Read the result above; launching a window is not test acceptance.'
"@
}

function Start-PaytmOperationsElevatedReview {
    param([string]$Runner, [string]$Evidence, [string]$OutputDirectory)
    foreach ($path in @($Runner, $Evidence)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "OPS_LAUNCH_INPUT_MISSING: $path" }
    }
    $runnerPath = (Get-Item -LiteralPath $Runner).FullName
    $evidencePath = (Get-Item -LiteralPath $Evidence).FullName
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $executable = Resolve-PaytmOperationsPowerShell
    $command = New-PaytmOperationsElevatedCommand $runnerPath $evidencePath $outputPath
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Write-Host '[LAUNCH] Windows will request administrator approval. Approve UAC, then continue in the NEW PowerShell 7 window.'
    try {
        # Intentionally visible: owner confirmation and clipboard exchange are interactive.
        $process = Start-Process -FilePath $executable -Verb RunAs -ArgumentList "-NoLogo -NoProfile -NoExit -EncodedCommand $encoded" -WorkingDirectory (Split-Path -Parent $runnerPath) -PassThru -ErrorAction Stop
    } catch {
        $cause = $_.Exception
        while ($cause) {
            if ($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 1223) {
                throw 'OPS_ELEVATION_CANCELLED: UAC was cancelled. No review was started.'
            }
            $cause = $cause.InnerException
        }
        throw 'OPS_ELEVATED_LAUNCH_FAILED: No review completion is confirmed. Check PowerShell 7 installation and Windows elevation policy.'
    }
    Write-Host "[LAUNCHED] Process $($process.Id). This is NOT a passed test. Continue only in the new window; share its final ONE JSON report."
}
