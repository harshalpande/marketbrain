# Real local child process only; synthetic text, no database or Docker.
#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$exe=(Get-Process -Id $PID).Path
$inputJson='{"password":"synthetic-only-\u20b9"}'
$child='$text=[Console]::In.ReadToEnd();[Console]::Out.Write($text.Length)'
$r=Invoke-PaperCatalogProcess $exe @('-NoProfile','-Command',$child) $PSScriptRoot 15 $inputJson
if($r.exitCode -ne 0 -or $r.timedOut -or [int]$r.stdout -ne $inputJson.Length -or $r.stderr){throw 'STDIN_TRANSPORT_FAILED'}
Write-Host 'PASS: bounded stdin transport and EOF delivery; no secret command argument or echo.'
