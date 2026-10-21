#Requires -Version 5.1
$ErrorActionPreference='Stop'
$capture=[pscustomobject]@{Command=$null;Arguments=$null;Window=$null;Calls=0;Present=$true;OnPath=$true}
function Get-Command { param($Name,$CommandType,$ErrorAction) if($capture.OnPath){[pscustomobject]@{Source='C:\Synthetic PuTTY\puttygen.exe'}} }
function Test-Path { param($LiteralPath,$PathType) return $capture.Present }
function Start-Process { param($FilePath,$ArgumentList,$WindowStyle) $capture.Command=$FilePath;$capture.Arguments=$ArgumentList;$capture.Window=$WindowStyle;$capture.Calls++ }
$runner=Join-Path $PSScriptRoot 'OpenVpsAdminKeyGenerator.ps1'
& $runner
if($capture.Command -cne 'C:\Synthetic PuTTY\puttygen.exe' -or ($capture.Arguments -join ' ') -cne '-t ed25519 -E sha256' -or $capture.Window -cne 'Normal' -or $capture.Calls -ne 1){throw 'Incorrect interactive launch.'}
$capture.OnPath=$false
& $runner
if($capture.Command -cne (Join-Path $env:ProgramFiles 'PuTTY\puttygen.exe') -or $capture.Calls -ne 2){throw 'Standard installation fallback failed.'}
$capture.Present=$false
$rejected=$false
try { & $runner } catch { if($_.Exception.Message -notlike 'PuTTYgen was not found*'){throw};$rejected=$true }
if(-not $rejected -or $capture.Calls -ne 2){throw 'Missing tool launched a process.'}
$capture.Present=$true
$gatewayOutput=(& $runner -Purpose Gateway 6>&1 | Out-String)
if($capture.Calls -ne 3 -or ($capture.Arguments -join ' ') -cne '-t ed25519 -E sha256' -or $gatewayOutput -notlike '*marketbrain-paytm-gateway.ppk*' -or $gatewayOutput -notlike '*Do not load, overwrite or reuse*'){throw 'Gateway purpose or identity separation missing.'}
$invalidRejected=$false
try { & $runner -Purpose Invalid } catch { $invalidRejected=$true }
if(-not $invalidRejected -or $capture.Calls -ne 3){throw 'Invalid purpose opened a process.'}
Write-Host 'PASS: five mocked launcher scenarios. No GUI launched, no keys generated, no VPS access.'
