#requires -Version 7.5
param([switch]$PreserveCompletedPendingResult,[switch]$RequireElevation)
$ErrorActionPreference='Stop'
if($RequireElevation){
 $currentIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{$currentElevated=([Security.Principal.WindowsPrincipal]::new($currentIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$currentIdentity.Dispose()}
 if(-not $currentElevated){throw 'RUNNER_ADMIN_REQUIRED: open PowerShell 7 as Administrator under the paired user. Existing runner unchanged.'}
}
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$installed=Join-Path $root 'runner\Start-AutomationWorker.ps1'
$source=Join-Path $PSScriptRoot 'Start-AutomationWorker.ps1'
if (-not (Test-Path -LiteralPath $installed)) { throw 'Existing runner not found. Do not initialize another account.' }
$pendingPath=Join-Path $root 'pending.json'
if (Test-Path -LiteralPath $pendingPath) {
    if(-not $PreserveCompletedPendingResult){throw 'Runner has pending work. Preserve it and finish that job before updating.'}
    if((Get-Item -LiteralPath $pendingPath).Length -gt 262144){throw 'Pending result too large; preserve for review.'}
    $pendingValue=Get-Content -LiteralPath $pendingPath -Raw|ConvertFrom-Json -DateKind String
    if($pendingValue.state -notin @('SUCCEEDED','FAILED','INTERRUPTED') -or $pendingValue.id -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'Only a completed pending result may be preserved during this update. Running work remains blocked.'}
    Write-Host 'Completed pending result will be retained and redelivered without rerunning its job.'
}
$oldHash=(Get-FileHash -LiteralPath $installed).Hash
$newHash=(Get-FileHash -LiteralPath $source).Hash
if ($oldHash -notin @('35F32FD988D95B95DB2972446F3968025E42469A2B633E9D982C4DB133728714','0D536851D5CD5F838C915615CADE3A3D81AB4ACB5645EF0F49EDC8F0B74DBA2F','8E5E062EC807098BFB1DA230EBCF6EE6F8E0478E363CB7C465858A5FE997E537','C1BD5F12658889D310341B3C477A2760510BD486BD3ECC1A5DCF53BD981C1C5B','51D0D42D43E90B539058F70999BB81A246CA9DABB0DE1F8D147CBD4EE54B23AF','5837E8F3C85CC98F77FAC7F79BD13F7DDDDF2C072DEAA24B2199ADC1B37BB9BA','A631EE9B1C675AA392C740C104D5E7F0E7797B16DE227C7A215E6C4B0EE3C391','C6FFB38A54DFC1A8BC7A0ED685F3F2C7EF68F24900CA4AEA027C2FF2D7A55783','DCF48A29C29D2CFC2849B0226FBB8A1ABB72F3AA505FEB0A291AAB4F12F4A662','14BA08C60CB47EEED0B9B667B825FD7A398C66034FAA20B0D65018C8DDAD2235',$newHash)) { throw 'Installed runner differs from reviewed baseline. Stop for review.' }
# Parse every source before stopping the working runner.
foreach($name in @('Automation.Common.ps1','Automation.Diagnostics.ps1','Automation.TestExecution.ps1','Start-AutomationWorker.ps1')) {
    $tokens=$null; $parseErrors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw "Source parse failed: $name"}
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$pattern='(?i)(?:^|\s)-File\s+(?:"'+[regex]::Escape($installed)+'"|'+[regex]::Escape($installed)+')(?:\s|$)'
$targets=@(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine -match $pattern })
foreach($target in $targets) {
    $owner=Invoke-CimMethod -InputObject $target -MethodName GetOwner
    if ($owner.ReturnValue -ne 0 -or ($owner.Domain+'\'+$owner.User) -ine $identity) { throw 'Runner process owner mismatch' }
}
if ($targets.Count -gt 1) { throw 'Multiple matching runner processes found; inspect before updating.' }
foreach($target in $targets) {
    $current=Get-CimInstance Win32_Process -Filter "ProcessId=$($target.ProcessId)"
    if (-not $current -or $current.CreationDate -ne $target.CreationDate -or $current.CommandLine -notmatch $pattern) { throw 'Runner process identity changed; stop for review.' }
    Stop-Process -Id $target.ProcessId -ErrorAction Stop
    Wait-Process -Id $target.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
}
# If command-line inspection missed a worker (for example due to elevation),
# refuse to replace files while it still owns the shared process mutex.
$mutex=[Threading.Mutex]::new($false,'Global\MarketBrainAutomationWorker')
$held=$false
try {
    try { $held=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held=$true }
    if (-not $held) { throw 'Existing runner is still active. Run this updater with the same Windows account and elevation as that runner.' }
# Preserve pending state if a claim raced with the stop. New worker marks it
# interrupted, rather than repeating the job. No credentials or state reset.
$backup=Join-Path $root ('runner-backup-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach($name in @('Start-AutomationWorker.ps1','Automation.Diagnostics.ps1','Automation.Common.ps1','Automation.TestExecution.ps1')) {
    $previous=Join-Path (Split-Path $installed) $name
    if (Test-Path -LiteralPath $previous) { Copy-Item -LiteralPath $previous -Destination $backup }
}
foreach($name in @('Automation.Common.ps1','Automation.Diagnostics.ps1','Automation.TestExecution.ps1','Start-AutomationWorker.ps1')) {
    $destination=Join-Path (Split-Path $installed) $name
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination ($destination+'.new')
    [IO.File]::Move(($destination+'.new'),$destination,$true)
}
} finally { if($held){$mutex.ReleaseMutex()}; $mutex.Dispose() }
$exe=(Get-Process -Id $PID).Path
$nonce=[guid]::NewGuid().ToString('N')
$expectedHelper=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')).Hash
$expectedExecution=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Automation.TestExecution.ps1')).Hash
$runnerArguments=@('-NoProfile','-WindowStyle','Hidden','-File',('"'+$installed+'"'),'-StartupNonce',$nonce)
if($RequireElevation){$runnerArguments+='-RequireElevation'}
$process=Start-Process -FilePath $exe -ArgumentList $runnerArguments -WindowStyle Hidden -PassThru
$watch=[Diagnostics.Stopwatch]::StartNew()
$verified=$false
do {
    $process.Refresh()
    if ($process.HasExited) { throw "Replacement runner exited with code $($process.ExitCode). Installation preserved; no success claimed." }
    $statusPath=Join-Path $root 'worker-status.json'
    if (Test-Path -LiteralPath $statusPath) {
        $status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        if ($status.startupNonce -ceq $nonce -and $status.processId -eq $process.Id -and $status.runnerSha256 -ceq $newHash -and $status.diagnosticsSha256 -ceq $expectedHelper -and $status.executionSha256 -ceq $expectedExecution) { if($RequireElevation -and $status.elevated -ne $true){throw 'RUNNER_ELEVATION_NOT_VERIFIED: replacement did not confirm administrator rights.'};$verified=$true;break }
    }
    Start-Sleep -Milliseconds 500
} while ($watch.Elapsed.TotalSeconds -lt 30)
if (-not $verified) { throw 'New runner startup was not confirmed. Preserve worker-status.json and connection-status.json; do not pair again.' }
if($RequireElevation){Write-Host 'RUNNER_ELEVATION_VERIFIED: replacement process confirmed administrator rights.'}
Write-Host 'RUNNER_UPDATE_VERIFIED: replacement process loaded the expected runner and diagnostic helper. Pairing and reports preserved.'
Write-Host "Runner SHA256: $newHash"
Write-Host 'Tell the development agent the update completed. No manual Paytm test or file transfer is needed.'
