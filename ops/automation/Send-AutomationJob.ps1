#requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateSet('diagnostic','intervention-test')][string]$Kind='diagnostic',
    [string]$JobId,
    [switch]$ReadOnly,
    [switch]$Cancel,
    [ValidateRange(1,900)][int]$WaitSeconds=360
)
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
$root = Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$config = Get-AutomationConfig (Join-Path $root 'controller.dpapi')
if ($config.role -ne 'controller') { throw 'Controller pairing required' }
if (($ReadOnly -or $Cancel) -and -not $JobId) { throw 'Supply the saved JobId' }
if (-not $JobId) { $JobId=[guid]::NewGuid().ToString() }
if ($JobId -cne ([guid]$JobId).ToString()) { throw 'Invalid JobId' }
$directory = Join-Path $root 'reports'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$path = Join-Path $directory ($JobId+'.json')
Write-Host "Job ID: $JobId"
# Save the identity before network access. Reuse this ID after a lost response.
Write-AutomationState (Join-Path $root 'last-request.json') @{id=$JobId;kind=$Kind}
if ($Cancel) { $null = Invoke-AutomationApi $config '/cancel' @{id=$JobId} }
elseif (-not $ReadOnly) { $null = Invoke-AutomationApi $config '/submit' @{id=$JobId;kind=$Kind} }
$timer=[Diagnostics.Stopwatch]::StartNew()
$last=''
do {
    $job=(Invoke-AutomationApi $config '/result' @{id=$JobId}).job
    if ($null -eq $job) { throw 'Job not found' }
    Write-AutomationState $path $job
    if ($job.state -ne $last) {
        Write-Host "$($job.state): $JobId"
        if ($job.state -eq 'WAITING_FOR_USER') { Write-Host $job.result.instruction }
        $last=$job.state
    }
    Write-Progress -Activity 'MarketBrain remote job' -Status "$($job.state); elapsed $([int]$timer.Elapsed.TotalSeconds)s" -PercentComplete -1
    if ($job.state -in @('SUCCEEDED','FAILED','INTERRUPTED','CANCELLED')) {
        Write-Progress -Activity 'MarketBrain remote job' -Completed
        Write-Host "Report automatically saved: $path"
        $job | ConvertTo-Json -Depth 12
        if ($job.state -ne 'SUCCEEDED') { throw "Remote job ended: $($job.state). Report retained at $path" }
        return
    }
    Start-Sleep -Seconds 3
} while ($timer.Elapsed.TotalSeconds -lt $WaitSeconds)
Write-Progress -Activity 'MarketBrain remote job' -Completed
Write-Host "Still pending. Fetch without resubmitting: .\ops\automation\Send-AutomationJob.ps1 -ReadOnly -JobId '$JobId'"
