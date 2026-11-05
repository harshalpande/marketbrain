#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$checks=0
function Check($Ok,$Label){if(-not $Ok){throw "SESSION_NATIVE_TEST_$Label"};$script:checks++}
$first=Get-PaytmInteractiveSession
$second=Get-PaytmInteractiveSession
Check ($first.authenticationId -cmatch '^[A-F0-9]{16}$') 'LOGON_ID_FORMAT'
Check ($first.authenticationId -ceq $second.authenticationId) 'NEW_CHILD_PROCESS_NOT_NEW_LOGON'
Check ($first.userSidHash -ceq $second.userSidHash) 'SAME_USER'
Check ($first.sessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId) 'SAME_SESSION'
Check ($first.sessionId -eq $second.sessionId) 'CHILD_SESSION_UNCHANGED'
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
try{Check ($first.userSidHash -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($id.User.Value)))) 'NATIVE_USER_MATCH'}finally{$id.Dispose()}
[pscustomobject]@{status='GATEWAY_SESSION_NATIVE_QUERY_PASSED';assertions=$checks;nativeWindowsQuery=$true;sessionChangesPerformed=$false;gatewayAccessed=$false}|ConvertTo-Json
