#Requires -Version 5.1
# Real Windows TCP inventory and owned child process; loopback only, no VPS or broker.
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$handle=$null
try {
    $listener.Start()
    $port=$listener.LocalEndpoint.Port
    $rows=@(Get-TunnelListeners $port)
    Assert-TunnelListenerRows $rows $PID -Port $port; $checks++
    $evidence=New-Object 'Collections.Generic.List[object]'
    $failed=$false
    try {Assert-TunnelListenerRows $rows 0 -Port $port -Evidence $evidence}catch{$failed=$true}
    Check ($failed -and $evidence[0].reasons -contains 'OWNER_PID_MISMATCH' -and $evidence[0].rows[0].owningProcess -eq $PID) 'Real foreign owner was accepted or evidence lost'
    $listener.Stop()
    Check (@(Get-TunnelListeners $port).Count -eq 0) 'Owned listener did not close'
    # The free ephemeral port is checked again by binding; a race fails, never displaces anyone.
    $childCommand='$ErrorActionPreference="Stop"; $fixtureListener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,'+$port+'); try {$fixtureListener.Start(); [Console]::Out.Write("CHILD_LISTENING"); Start-Sleep -Seconds 45} finally {$fixtureListener.Stop()}'
    $executable=Join-Path $PSHOME 'powershell.exe'
    if(-not (Test-Path -LiteralPath $executable)){$executable=Join-Path $PSHOME 'pwsh.exe'}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $handle=Start-TunnelProcess $executable @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
    $childEvidence=New-Object 'Collections.Generic.List[object]'
    Wait-TunnelListener $handle $port -Evidence $childEvidence -Label 'Real owned Windows child'
    Check ($childEvidence.Count -gt 0 -and $childEvidence[$childEvidence.Count-1].valid) 'Real child listener rejected'
    Check ($childEvidence[$childEvidence.Count-1].rows[0].owningProcess -eq $handle.Process.Id -and $handle.Process.Id -ne $PID) 'Child ownership did not match exact process handle'
    $result=Complete-TunnelProcess $handle -StopNow
    Check ($result.StoppedByRunner -and $result.Stdout -eq 'CHILD_LISTENING') 'Child start/owned cleanup not captured'
    Check (@(Get-TunnelListeners $port).Count -eq 0) 'Child listener remains after termination'
    Write-Host "PASS: $checks real Windows loopback/child-process checks. No SSH, Pageant, VPS or broker used."
} finally {
    $listener.Stop()
    if($null -ne $handle){Complete-TunnelProcess $handle -StopNow | Out-Null}
}
