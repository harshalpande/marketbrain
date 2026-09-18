#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunDirectory,[switch]$Watch,[ValidateRange(1,60)][int]$PollSeconds=5)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TypedDecisionSweep.ps1')
try {
    do {
        $report=$null
        try { $report=ConvertFrom-SweepJson (Get-Content -LiteralPath (Join-Path $RunDirectory 'sweep.json') -Raw) }
        catch { if (-not $Watch) { throw }; Write-Warning 'Checkpoint temporarily unavailable; waiting for next poll.' }
        if ($null -ne $report) {
            $age=([DateTime]::UtcNow-[DateTime]::Parse($report.updatedAt).ToUniversalTime()).TotalSeconds
            $owner=Get-Process -Id $report.ownerPid -ErrorAction SilentlyContinue
            $alive=$null -ne $owner -and $owner.StartTime.ToUniversalTime().ToString('o') -eq $report.ownerStartedAt
            $display=$report.status
            if ($report.status -eq 'RUNNING' -and (-not $alive -or $age -gt 60)) { $display='STALE_OR_INTERRUPTED_CHECKPOINT' }
            $text='{0}; {1}/{2}; heartbeat age={3:N0}s; {4}' -f $display,$report.completedTaskCount,$report.tasks.Count,$age,$report.detail
            Write-Progress -Id 91 -Activity 'Configuration sweep monitor' -Status $text -PercentComplete $report.progressPercent
            Write-Host "[$($report.progressPercent)%] $text"
            if ($display -ne 'RUNNING') { break }
        }
        if ($Watch) { Start-Sleep -Seconds $PollSeconds }
    } while ($Watch)
} finally { Write-Progress -Id 91 -Activity 'Configuration sweep monitor' -Completed }
