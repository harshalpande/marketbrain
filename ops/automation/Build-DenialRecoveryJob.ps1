#requires -Version 7.5
param([switch]$Check,[ValidateSet('Activation','Lifecycle','RecoveryUpgrade','RecoveryActivation')][string]$Stage='RecoveryActivation')
$ErrorActionPreference='Stop'
if($Stage -eq 'RecoveryUpgrade'){& (Join-Path $PSScriptRoot 'Build-CollectorRecoveryJob.ps1') -Check:$Check;return}
$parts=@'
#requires -Version 7.5
# Generated bounded activation. Historical recovery revisions remain immutable.
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
'@
$parts=@($parts)
function Add-Functions([string]$Path,[string[]]$Names) {
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $Path),[ref]$t,[ref]$e)
 if($e.Count){throw 'SOURCE_PARSE_FAILED'}
 foreach($name in $Names){$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true);if(-not $fn){throw ('Missing '+$name)};$script:parts+=$fn.Extent.Text}
}
Add-Functions '../windows/PaytmTimeAccountProbe.ps1' @('Resolve-TimeAccountTaskSid')
Add-Functions '../windows/PaytmDurableCollectorSetup.ps1' @('Get-DurableCollectorDefinition','Assert-DurableCollectorTask')
foreach($file in @('PaytmTimeObservation.ps1','PaytmDurableCollector.ps1','PaytmDurableCollectorPreflight.ps1')){$parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot ('../windows/'+$file)))}
Add-Functions 'DenialRecovery.Core.ps1' @('Stop-DenialRecoveryTask','Register-DenialRecoveryGuard','Remove-DenialRecoveryGuard')
Add-Functions 'PostRecovery.Core.ps1' @('Get-PostRecoveryPreflight','Get-ApplicationHealthInventory')
Add-Functions '../windows/PaytmCollectorGatewayWindow.ps1' @('Read-BoundedJson','New-CollectorGatewayContext','Get-CollectorGatewayPreflight','Test-CollectorGatewaySample','Start-CollectorGatewayWindow')
$receipt=Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/queued-recovery-preflight-20261120.json') -Raw|ConvertFrom-Json -AsHashtable -DateKind String
$json=$receipt|ConvertTo-Json -Depth 12 -Compress
$parts+=('$acceptedGatewayReceipt = @'+"'`n"+$json+"`n'@ | ConvertFrom-Json -AsHashtable -DateKind String")
if($Stage -eq 'RecoveryActivation'){
 . (Join-Path $PSScriptRoot 'CollectorRecoveryActivation.ps1')
 $parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CollectorRecoveryActivation.ps1'))
 $parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CollectorGatewayIncident.ps1'))
 $parts+=ConvertTo-RecoveryActivationSource ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DurableActivation.Entry.ps1')))
}
elseif($Stage -eq 'Activation'){$parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DurableActivation.Entry.ps1'))}
else{
 Add-Functions 'DurableActivation.Entry.ps1' @('Set-CollectorActivationControl','Test-CollectorActivationSample','Stop-CollectorActivation')
 $native=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../windows/ReadPaytmInteractiveSession.ps1'))
 $parts+=('$interactiveSessionCode = '+"'"+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($native))+"'")
 $parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CollectorLifecycle.Entry.ps1'))
}
$built=($parts -join "`n`n").Replace("`r`n","`n")
$old='$receipt=Get-Content -LiteralPath (Join-Path $PSScriptRoot ''../../docs/evidence/queued-recovery-preflight-20261120.json'') -Raw|ConvertFrom-Json -AsHashtable'
if(-not $built.Contains($old)){throw 'RECEIPT_TEMPLATE_CHANGED'}
$built=$built.Replace($old,'$receipt=$acceptedGatewayReceipt')
if($Stage -eq 'RecoveryActivation'){
 $old="if(-not `$r.passed){throw `$r.failure}"
 if(-not $built.Contains($old)){throw 'GATEWAY_REVIEW_TEMPLATE_CHANGED'}
 $built=$built.Replace($old,'if(-not $r.passed){$r=Get-CollectorReviewedGatewayPreflight $Context $r}')
 $old=' $Context.startAttempted=$true'
 if(-not $built.Contains($old)){throw 'GATEWAY_ARCHIVE_TEMPLATE_CHANGED'}
 $built=$built.Replace($old," Preserve-CollectorGatewayIncident `$Context `$again`n"+$old)
}
$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($built,[ref]$t,[ref]$e)
if($e.Count -or [Text.Encoding]::UTF8.GetByteCount($built) -gt 65536){throw 'INVALID_ACTIVATION_ARTIFACT'}
$path=Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'
if($Check){if([IO.File]::ReadAllText($path).Replace("`r`n","`n") -cne $built){throw 'ACTIVATION_ARTIFACT_STALE'}}else{[IO.File]::WriteAllText($path,$built,[Text.UTF8Encoding]::new($false))}
Write-Host ('DURABLE_ACTIVATION_BUILD_VERIFIED bytes='+[Text.Encoding]::UTF8.GetByteCount($built))
