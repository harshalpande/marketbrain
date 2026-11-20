#requires -Version 7.5
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DurableActivation.Entry.ps1'))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'PARSE_FAILED'}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
foreach($case in @('valid','orders','wrongInstance','failed','backoff','regression','impossibleCount','repeat')){
 $state=@{instance=('a'*32);sequence=2;advances=1}
 $v=@{version=1;instanceId=('a'*32);processId=12;ordersEnabled=$false;failure=$null;phase='HEALTH_RECORDED';consecutiveFailures=0;sequence=3;acceptedCount=3}
 switch($case){orders{$v.ordersEnabled=$true} wrongInstance{$v.instanceId='b'*32} failed{$v.failure='failed'} backoff{$v.phase='BACKOFF'} regression{$v.sequence=1} impossibleCount{$v.acceptedCount=9} repeat{$v.sequence=2;$v.acceptedCount=2}}
 $failed=$false;$ok=$false;try{$ok=Test-CollectorActivationSample $v $state}catch{$failed=$true}
 if($failed -ne ($case -notin @('valid','repeat')) -or $ok -ne ($case -eq 'valid')){throw ('SAMPLE_CASE_'+$case)}
}
# Run orchestration with fixed OS substitutes; no real task/network/credential access.
$body=$source.Substring($source.IndexOf('$r=@{version=1;runId='))
$begin=$body.IndexOf(' $identity=[Security.Principal.WindowsIdentity]');$end=$body.IndexOf(' $receipt=Read-TimeObservationFile',$begin)
if($begin -lt 0 -or $end -lt 0){throw 'FIXTURE_TEMPLATE_CHANGED'}
$body=$body.Remove($begin,$end-$begin).Replace('if(-not $r.passed){exit 1}','')
function Read-TimeObservationFile {return @{runId='ab47639ee8d74da69a9466c0f59e601e';workerSha256=('A'*64)}}
function Get-DurableCollectorStagingPreflight {if($script:case -eq 'preflight'){throw 'FIXTURE_PREFLIGHT'};return @{passed=$true}}
function Get-DurableCollectorDefinition {return @{root=$script:temp;work=$script:temp;name='FIXTURE'}}
function New-CollectorGatewayContext {return @{startAttempted=$false;guardAttempted=$false;guardXmlHash=$null;stopped=$false}}
function Get-CollectorGatewayPreflight {return @{passed=$true}}
function Start-CollectorGatewayWindow($Context){$Context.guardAttempted=$true;if($script:case -eq 'guard'){throw 'FIXTURE_GUARD'};$Context.guardXmlHash='fixed';$Context.startAttempted=$true}
function Set-CollectorActivationControl {$script:controlWrites++}
function Enable-ScheduledTask {$script:enables++}
function Start-ScheduledTask {if($script:case -eq 'start'){throw 'FIXTURE_START'}}
function Get-ScheduledTask {return @{State='Running'}}
function Get-ScheduledTaskInfo {return @{LastTaskResult=0}}
function Start-Sleep {}
function Test-Path {param($LiteralPath) if($LiteralPath.EndsWith('status.json')){return ($script:enables -gt 0)};return $false}
function Read-BoundedJson($Path){
 $script:seq++
 $v=@{version=1;instanceId=('a'*32);processId=12;sequence=$script:seq;acceptedCount=$script:seq;ordersEnabled=$false;phase='HEALTH_RECORDED';consecutiveFailures=0;failure=$null}
 if($script:case -eq 'publication'){$v.failure='failed'}
 if($Path.EndsWith('final.json')){$v.phase='STOPPED';$v.finalHealthRevoked=($script:case -ne 'revocation');return @{runId='ab47639ee8d74da69a9466c0f59e601e';ordersEnabled=$false;nonAdmin=$true;sessionId=0;tokenAuthenticated=$true;applicationLocked=$true;collector=$v}}
 return $v
}
function Stop-CollectorActivation($Definition,$Report){if($script:case -eq 'collectorStop'){throw 'FIXTURE_STOP'};$Report.collectorStopped=$true}
function Stop-DenialRecoveryTask {if($script:case -eq 'gatewayStop'){throw 'FIXTURE_STOP'}}
function Remove-DenialRecoveryGuard {$script:removed++}
foreach($script:case in @('valid','preflight','guard','start','publication','revocation','collectorStop','gatewayStop')){
 $script:temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-activation-fixture-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($temp)
 [IO.File]::WriteAllText((Join-Path $temp 'instance.lock'),'')
 $ResultPath=Join-Path $temp 'report.json';$Mode='Apply';$script:enables=0;$script:removed=0;$script:seq=0;$script:controlWrites=0
 & ([scriptblock]::Create($body))
 $r=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
 if($r.passed -ne ($case -eq 'valid')){throw ('WORKFLOW_CASE_'+$case)}
 if($case -in @('preflight','guard') -and $enables){throw 'ENABLED_BEFORE_GUARD'}
 if($case -in @('collectorStop','gatewayStop') -and $removed){throw 'REMOVED_GUARD_BEFORE_STOP'}
 if($case -in @('valid','start','publication','revocation') -and $removed -ne 1){throw 'GUARD_NOT_CLEANED'}
}
Write-Host 'DURABLE_ACTIVATION_FIXTURES_PASSED: 8 sample cases and 8 orchestration/cleanup cases.'
