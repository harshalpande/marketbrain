#requires -Version 7.5
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Parser errors'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-TransportPreflightEvidence'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$state=[pscustomobject]@{phase='BLOCKED';failure='TRANSPORT_DENIAL_FAILED';instanceId=('a'*32);sequence=3860;ordersEnabled=$false;brokerReady=$false;secret='NEVER_RETURN'}
$e=Get-TransportPreflightEvidence $state ([pscustomobject]@{mode='LOCKED'})
if(-not $e.applicationLocked -or $e.failure -ne 'TRANSPORT_DENIAL_FAILED' -or $e.ContainsKey('secret')){throw 'Blocked evidence failed'}
$state.failure='sensitive raw text';$state.instanceId='../bad';$state.ordersEnabled=$true
$e=Get-TransportPreflightEvidence $state ([pscustomobject]@{mode='LOCKED'})
if($e.applicationLocked -or $e.ContainsKey('failure') -or $e.ContainsKey('instanceId')){throw 'Unsafe evidence accepted'}
Write-Host 'PREFLIGHT_FIXTURES_PASSED: locked blocked state identified, raw fields excluded, orders-enabled rejected.'
