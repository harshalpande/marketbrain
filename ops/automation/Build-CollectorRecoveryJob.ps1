#requires -Version 7.5
param([switch]$Check)
$ErrorActionPreference='Stop'
$w=Join-Path $PSScriptRoot '../windows'
. "$w/PaytmHealthScheduledToken.ps1"
. "$w/PaytmDurableCollectorSetup.ps1"
. "$w/PaytmCollectorRecoverySource.ps1"
$worker=(New-CollectorRecoverySource).Replace("`r`n","`n")
$bytes=[Text.Encoding]::UTF8.GetBytes($worker)
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
$ms=[IO.MemoryStream]::new();$zip=[IO.Compression.GZipStream]::new($ms,[IO.Compression.CompressionLevel]::Optimal,$true)
$zip.Write($bytes,0,$bytes.Length);$zip.Dispose();$payload=[Convert]::ToBase64String($ms.ToArray());$ms.Dispose()
$parts=@("#requires -Version 7.5`nparam([Parameter(Mandatory)][string]`$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]`$Mode='Observe',[switch]`$LocalPassword)`n`$ErrorActionPreference='Stop'")
function Add-Function([string]$Path,[string[]]$Names){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e);if($e.Count){throw 'SOURCE_PARSE'}
 foreach($name in $Names){$f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true);if(-not $f){throw 'SOURCE_FUNCTION_MISSING'};$script:parts+=$f.Extent.Text}
}
Add-Function "$w/PaytmTimeAccountProbe.ps1" @('Resolve-TimeAccountTaskSid','Test-TimeAccountCredential')
Add-Function "$w/PaytmDurableCollectorSetup.ps1" @('Get-DurableCollectorDefinition','Assert-DurableCollectorTask')
foreach($file in @('PaytmTimeObservation.ps1','PaytmDurableCollectorPreflight.ps1','PaytmCollectorRecovery.ps1','PaytmCollectorObserverRecovery.ps1')){$parts+=[IO.File]::ReadAllText((Join-Path $w $file))}
Add-Function (Join-Path $PSScriptRoot 'CollectorLifecycle.Entry.ps1') @('Invoke-CollectorDockerRead','Get-CollectorDockerState')
$parts+="`$upgradeWorkerHash='$hash'`n`$upgradePayload='$payload'"
$parts+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CollectorRecoveryUpgrade.Entry.ps1'))
$built=($parts -join "`n`n").Replace("`r`n","`n")
foreach($source in @($worker,$built)){$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e);if($e.Count){throw 'UPGRADE_SOURCE_PARSE'}}
if([Text.Encoding]::UTF8.GetByteCount($built) -gt 65536){throw 'UPGRADE_ARTIFACT_SIZE'}
$path=Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'
if($Check){if([IO.File]::ReadAllText($path).Replace("`r`n","`n") -cne $built){throw 'UPGRADE_ARTIFACT_STALE'}}else{[IO.File]::WriteAllText($path,$built,[Text.UTF8Encoding]::new($false))}
Write-Host ('COLLECTOR_UPGRADE_BUILD_VERIFIED bytes={0}; worker={1}' -f [Text.Encoding]::UTF8.GetByteCount($built),$hash)
