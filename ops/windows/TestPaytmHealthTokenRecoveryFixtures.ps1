#Requires -Version 5.1
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmHealthTokenRecovery.ps1"
$count=0
function Check([bool]$Value){if(-not $Value){throw 'RECOVERY_FIXTURE_FAILED'};$script:count++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed}
# Path/ACL ownership is independently checked by the existing account helpers at runtime.
function Assert-PaytmAccountPath([string]$Path){$Path}
$root=Join-Path ([IO.Path]::GetTempPath()) ('health-recovery-fixture-'+[guid]::NewGuid().ToString('N'))
$dir=Join-Path $root 'custody';$work=Join-Path $root 'work'
$null=New-Item -ItemType Directory -Path $dir,$work
$library=Join-Path $dir 'library.ps1';$extra=Join-Path $dir 'health-token.dpapi';$cipher=Join-Path $work 'token-test.dpapi'
try{
 [IO.File]::WriteAllText($library,'fixture library')
 $e=[pscustomobject]@{sourceHashes=[pscustomobject]@{'PaytmHealthTokenCustody.ps1'=(Get-FileHash -LiteralPath $library).Hash}}
 Assert-HealthTokenRecoveryFiles $dir $work $e;Check $true
 [IO.File]::WriteAllText($extra,'fixture ciphertext');Reject {Assert-HealthTokenRecoveryFiles $dir $work $e};[IO.File]::Delete($extra)
 [IO.File]::WriteAllText($cipher,'fixture ciphertext');Reject {Assert-HealthTokenRecoveryFiles $dir $work $e};[IO.File]::Delete($cipher)
 [IO.File]::WriteAllText($library,'changed');Reject {Assert-HealthTokenRecoveryFiles $dir $work $e}
 Reject {Read-HealthTokenRecoveryEvidence $library}
 [IO.File]::Delete($library);Reject {Assert-HealthTokenRecoveryFiles $dir $work $e}
 [IO.Directory]::Delete($dir);Reject {Assert-HealthTokenRecoveryFiles $dir $work $e}
}finally{
 foreach($f in @($library,$extra,$cipher)){if([IO.File]::Exists($f)){[IO.File]::Delete($f)}}
 foreach($d in @($dir,$work,$root)){if([IO.Directory]::Exists($d)){[IO.Directory]::Delete($d)}}
}
Write-Host "PASS: $count token recovery file-state checks; no account or runtime changes."
