[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MonitoringDirectory = 'C:\MarketBrainData\Monitoring',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'MarketBrain-HealthCheck',

    [Parameter()]
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MonitoringDirectory -PathType Container)) {
    throw "Monitoring directory was not found at $MonitoringDirectory"
}

$existingHealthCheck = Join-Path $MonitoringDirectory 'HealthCheck.ps1'
if (-not (Test-Path -LiteralPath $existingHealthCheck -PathType Leaf)) {
    throw "Existing HealthCheck.ps1 was not found at $existingHealthCheck"
}

$sourceDirectory = $PSScriptRoot
Copy-Item `
    -LiteralPath (Join-Path $sourceDirectory 'RunHealthCheck.ps1') `
    -Destination $MonitoringDirectory `
    -Force
Copy-Item `
    -LiteralPath (Join-Path $sourceDirectory 'RunHealthCheckHidden.vbs') `
    -Destination $MonitoringDirectory `
    -Force

$hiddenLauncherPath = Join-Path $MonitoringDirectory 'RunHealthCheckHidden.vbs'
$taskAction = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\wscript.exe" `
    -Argument ('"{0}"' -f $hiddenLauncherPath)

$taskTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$taskSettings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

$taskPrincipal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $taskAction `
    -Trigger $taskTrigger `
    -Settings $taskSettings `
    -Principal $taskPrincipal `
    -Force |
    Out-Null

Write-Output "Scheduled task '$TaskName' now runs silently every $IntervalMinutes minutes."
Write-Output 'Daily health logs are retained for 30 days by default.'
