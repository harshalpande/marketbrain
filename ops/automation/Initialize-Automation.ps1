#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('controller','worker')][string]$Role)
$ErrorActionPreference='Stop'
$root = Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$configPath = Join-Path $root "$Role.dpapi"
if (Test-Path -LiteralPath $configPath) { throw "Already paired: $configPath. Do not overwrite an existing identity." }
Write-Host "Paste the $($Role.ToUpper())_PAIRING line privately. Input is hidden. Do not paste it into chat."
$secure = Read-Host 'Pairing line' -AsSecureString
$plain = [Net.NetworkCredential]::new('', $secure).Password
$plain = $plain -replace '^(CONTROLLER|WORKER)_PAIRING=', ''
$pairing = $plain | ConvertFrom-Json
if ($pairing.role -ne $Role -or $pairing.token -notmatch '^[a-f0-9]{64}$' -or $pairing.pin -notmatch '^[A-F0-9]{64}$' -or $pairing.url -notmatch '^https://[a-zA-Z0-9.-]+:18443$') { throw 'Wrong or invalid pairing line' }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$encrypted = ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString
[IO.File]::WriteAllText($configPath,$encrypted)
$plain=$null; $pairing=$null; $secure=$null
Write-Host "Paired as $Role using Windows user encryption. Configuration: $configPath"
if ($Role -eq 'worker') {
    $install = Join-Path $root 'runner'
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    foreach($name in @('Automation.Common.ps1','Automation.Diagnostics.ps1','Start-AutomationWorker.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $install $name)
    }
    Write-Host 'Next run Install-AutomationStartup.ps1 to start the runner and restore it at sign-in.'
}
