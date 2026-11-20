#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CollectorRecoveryActivation.ps1')
$source=ConvertTo-RecoveryActivationSource ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DurableActivation.Entry.ps1')))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e);if($e.Count){throw 'RECOVERY_PARSE'}
$f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Test-CollectorActivationSample'},$true)
. ([scriptblock]::Create($f.Extent.Text))
foreach($case in @('valid','oldVersion','orders','failed','backoff','differentWorker','sequence')){
 $state=@{instance=('a'*32);processId=12;sequence=2;advances=1}
 $v=@{version=2;instanceId=('a'*32);processId=12;ordersEnabled=$false;sequence=3;acceptedCount=3;consecutiveFailures=0;phase='HEALTH_RECORDED';failure=$null}
 switch($case){oldVersion{$v.version=1} orders{$v.ordersEnabled=$true} failed{$v.failure='failed'} backoff{$v.failure='COLLECTOR_SAMPLE_FAILED';$v.phase='BACKOFF';$v.consecutiveFailures=1} differentWorker{$v.processId=13} sequence{$v.sequence=1}}
 $failed=$false;$ok=$false;try{$ok=Test-CollectorActivationSample $v $state}catch{$failed=$true}
 if($failed -ne ($case -notin @('valid','backoff')) -or $ok -ne ($case -eq 'valid')){throw ('RECOVERY_SAMPLE_'+$case)}
}
foreach($case in @('valid','instance','count','phase')){
 $s=@{version=1;instanceId='9e0e85a010c2457887faa0fe8efdb6a1';processId=4400;phase='FAILED';failure='COLLECTOR_REVOCATION_UNCONFIRMED';acceptedCount=13;sequence=18;ordersEnabled=$false}
 switch($case){instance{$s.instanceId='other'} count{$s.acceptedCount=14} phase{$s.phase='HEALTH_RECORDED'}}
 $failed=$false;try{Assert-RecoveryPriorReports $s @{runId='ab47639ee8d74da69a9466c0f59e601e';collector=$s}}catch{$failed=$true}
 if($failed -ne ($case -ne 'valid')){throw ('RECOVERY_ARCHIVE_'+$case)}
}
# Run the established orchestration fixtures against the transformed entry as well.
$test=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Test-DurableActivation.ps1'))
$test=$test.Replace('$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot ''DurableActivation.Entry.ps1''))',"`$source=ConvertTo-RecoveryActivationSource ([IO.File]::ReadAllText((Join-Path `$PSScriptRoot 'DurableActivation.Entry.ps1')))")
$test=$test.Replace('version=1;instanceId','version=2;instanceId').Replace("' `$receipt=Read-TimeObservationFile'","'  `$receipt=Get-RecoveryCollectorReceipt'")
$test=$test.Replace('function Get-DurableCollectorStagingPreflight','function Get-RecoveryCollectorPreflight')
$test=$test.Replace('function Read-TimeObservationFile {return','function Get-RecoveryCollectorReceipt {return')
$test=$test.Replace('function Set-CollectorActivationControl {','function Preserve-RecoveryPriorReports {}' + "`n" + 'function Set-CollectorActivationControl {')
# PSScriptRoot in dynamic scripts is not stable: use a temporary script next to this test.
$path=Join-Path $PSScriptRoot ('fixture-'+[guid]::NewGuid().ToString('N')+'.ps1')
try{[IO.File]::WriteAllText($path,$test);& $path}finally{Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}
Write-Host 'RECOVERY_ACTIVATION_PASSED: seven sample, four archive-identity and inherited orchestration cases.'
