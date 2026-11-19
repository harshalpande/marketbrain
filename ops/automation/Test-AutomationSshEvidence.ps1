#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')
$v=[pscustomobject]@{lastSshObservation=[pscustomobject]@{exited=$true;authenticated=$false;stderrDrained=$true;reason='UNKNOWN';tags=@('KEX_CLOSED','SECRET');stderrSha256=('A'*64);raw='SECRET'};lastSshAttempt=13}
$r=Select-AutomationGatewayFields $v
if(-not $r.lastSshObservation.exited -or $r.lastSshObservation.tags.Count -ne 1 -or $r.lastSshObservation.ContainsKey('raw') -or $r.lastSshAttempt -ne 13){throw 'Sanitizer regression'}
if(($r|ConvertTo-Json -Depth 5) -match 'SECRET'){throw 'Unexpected data disclosed'}
Write-Host 'SSH_SANITIZER_PASSED'
