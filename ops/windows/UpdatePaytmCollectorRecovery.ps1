#requires -Version 7.5
#requires -RunAsAdministrator
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
. (Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1')
Assert-TimeObservationAcl $root
$report=Join-Path $root 'collector-upgrade-result.json'
if(Test-Path -LiteralPath $report){throw 'COLLECTOR_UPGRADE_RESULT_EXISTS: retain it for automated review before retrying.'}
Write-Host '[10%] Verify original stopped collector, existing time observer and running application.'
& (Join-Path $PSScriptRoot '../automation/jobs/PaytmDenialRecovery.ps1') -ResultPath $report -Mode Apply -LocalPassword
Write-Host 'COLLECTOR_RECOVERY_UPGRADE_VERIFIED. Kept disabled; runtime acceptance is next. Report ready for automatic collection.'
