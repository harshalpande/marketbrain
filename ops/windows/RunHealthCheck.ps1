[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MonitoringDirectory = $PSScriptRoot,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30
)

$ErrorActionPreference = 'Stop'

try {
    $healthCheckPath = Join-Path $MonitoringDirectory 'HealthCheck.ps1'
    $currentLogPath = Join-Path $MonitoringDirectory 'health.log'

    if (-not (Test-Path -LiteralPath $healthCheckPath -PathType Leaf)) {
        throw "Health check script was not found at $healthCheckPath"
    }

    # HealthCheck.ps1 appends to health.log. At the first run on a new day,
    # preserve yesterday's file as a dated archive before writing today's data.
    if (Test-Path -LiteralPath $currentLogPath -PathType Leaf) {
        $currentLog = Get-Item -LiteralPath $currentLogPath
        if ($currentLog.LastWriteTime.Date -lt [DateTime]::Today) {
            $archiveName = 'health-{0:yyyy-MM-dd}.log' -f $currentLog.LastWriteTime.Date
            $archivePath = Join-Path $MonitoringDirectory $archiveName

            if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
                Get-Content -LiteralPath $currentLogPath |
                    Add-Content -LiteralPath $archivePath
                Remove-Item -LiteralPath $currentLogPath -Force
            }
            else {
                Move-Item -LiteralPath $currentLogPath -Destination $archivePath
            }
        }
    }

    $retentionCutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $MonitoringDirectory -File -Filter 'health-*.log' |
        Where-Object LastWriteTime -LT $retentionCutoff |
        Remove-Item -Force

    & $healthCheckPath
}
catch {
    $errorLogName = 'health-runner-error-{0:yyyy-MM-dd}.log' -f (Get-Date)
    $errorLogPath = Join-Path $MonitoringDirectory $errorLogName
    '{0:o} | runner_error={1} | message={2}' -f `
        (Get-Date), $_.Exception.GetType().Name, $_.Exception.Message |
        Add-Content -LiteralPath $errorLogPath
    exit 1
}
