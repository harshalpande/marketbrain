#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory)][string]$RecoveryReportPath)
$ErrorActionPreference='Stop'
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $tempRoot ('mb-ssh-incident-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
function Get-Clipboard {param([switch]$Raw) $global:mbIncidentTestClipboard}
function Set-Clipboard {param($Value) $global:mbIncidentTestClipboard=$Value}
function Check($Value,$Message){if(-not $Value){throw $Message}}
try{
 & (Join-Path $PSScriptRoot 'GetPaytmSshIncident.ps1') -Phase Prepare
 Check ($global:mbIncidentTestClipboard.StartsWith('sudo -n python3')) 'Prepare command missing'
 Check ($global:mbIncidentTestClipboard.Contains('MB_SSH_INCIDENT')) 'Heredoc missing'
 foreach($case in @('valid','wrapped','empty','wrongWindow','incomplete','badReceipt')){
  $server=@{version=1;kind='PAYTM_SSH_INCIDENT_V1';since='2026-11-13 13:30:00 UTC';until='2026-11-13 13:35:00 UTC';readOnly=$true;success=$true;events=@()}
  if($case -eq 'wrongWindow'){$server.since='wrong'}
  if($case -eq 'incomplete'){$server.success=$false}
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($server|ConvertTo-Json)))
  if($case -eq 'wrapped'){$encoded=$encoded -replace '(.{40})',"`$1`n             "}
  $global:mbIncidentTestClipboard="BEGIN_PAYTM_SSH_INCIDENT`n$encoded`nEND_PAYTM_SSH_INCIDENT"
  if($case -eq 'empty'){$global:mbIncidentTestClipboard=''}
  $inputPath=$RecoveryReportPath
  if($case -eq 'badReceipt'){$inputPath=Join-Path $root 'wrong.json';'{}'|Set-Content $inputPath}
  $out=Join-Path $root $case
  $failed=$false
  try{& (Join-Path $PSScriptRoot 'GetPaytmSshIncident.ps1') -Phase Collect -RecoveryReportPath $inputPath -OutputDirectory $out}catch{$failed=$true}
  $files=@(Get-ChildItem $out -Filter '*.json')
  Check ($files.Count -eq 1) "Missing single report: $case"
  $r=Get-Content $files[0].FullName -Raw|ConvertFrom-Json
  Check ($failed -eq ($case -notin @('valid','wrapped'))) "Unexpected outcome: $case"
  Check (-not $r.gatewayChanged -and -not $r.taskStarted -and -not $r.exactConnectionMatchEstablished) "Scope claim: $case"
 }
 Write-Host 'PASS: prepare and six receipt/clipboard collection workflows.'
}finally{
 Remove-Variable mbIncidentTestClipboard -Scope Global -ErrorAction SilentlyContinue
 $resolved=[IO.Path]::GetFullPath($root)
 if(-not $resolved.StartsWith((Join-Path $tempRoot 'mb-ssh-incident-test-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Test cleanup outside temporary workspace'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
