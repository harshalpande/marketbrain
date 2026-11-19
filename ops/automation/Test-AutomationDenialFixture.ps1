#requires -Version 7.5
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Parser errors'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-LocalDenialFormatting'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$r=Test-LocalDenialFormatting
if(-not $r.passed -or $r.externalNetworkContacted -or $r.checks.Count -ne 3){throw ($r|ConvertTo-Json -Depth 6)}
$r|ConvertTo-Json -Depth 6
