#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmCollectorGatewayWindow.ps1')
function New-Sample {
 @{installationId='ea8b91471cf048aa97a0f6b939b355c7';instanceId=('b'*32);sequence=2;ordersEnabled=$false;brokerReady=$false;failure=$null;phase='TRANSPORT_READY';denialsVerified=$true;lastTlsObservation=@{exitCode=0;timedOut=$false;connectStatus=200;tlsVerifyCode=0}}
}
foreach($case in @('valid','old','orders','broker','blocked','tls','denials','pending')){
 $v=New-Sample
 switch($case){old{$v.instanceId='a'*32} orders{$v.ordersEnabled=$true} broker{$v.brokerReady=$true} blocked{$v.failure='BLOCKED'} tls{$v.lastTlsObservation.tlsVerifyCode=1} denials{$v.denialsVerified=$false} pending{$v.phase='CONNECTING'}}
 $failed=$false;$ready=$false;try{$ready=Test-CollectorGatewaySample $v ('a'*32)}catch{$failed=$true}
 if($failed -ne ($case -in @('orders','broker','blocked','tls','denials')) -or $ready -ne ($case -eq 'valid')){throw "Sample failed: $case"}
}
# Execute real start/stop control flow with isolated OS substitutes.
$startSource=(Get-Command Start-CollectorGatewayWindow).ScriptBlock.ToString().Replace('[Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()','(Get-FixtureListeners)')
function Get-FixtureListeners {return @{Port=18889;Address=$(if($script:case -eq 'wildcard'){'0.0.0.0'}else{'127.0.0.1'})}}
function Get-CollectorGatewayPreflight {
 $script:preflights++
 if($script:case -eq 'preflight'){throw 'FIXTURE_PREFLIGHT'}
 @{hashes=@{'manifest.json'='fixed';'status.json'=$(if($script:case -eq 'changed' -and $script:preflights -eq 2){'changed'}else{'fixed'})};currentStatus=@{instanceId=('a'*32)}}
}
function Test-Path {return $false}
function New-Item {}
function Register-DenialRecoveryGuard {param($Context,$ManifestHash) if($script:case -eq 'guard'){throw 'FIXTURE_GUARD'};$Context.guardXmlHash='fixture';$script:guardRegistered++}
function Remove-DenialRecoveryGuard {$script:guardRemoved++}
function Enable-ScheduledTask {$script:enabled++}
function Start-ScheduledTask {if($script:case -eq 'start'){throw 'FIXTURE_START'}}
function Stop-DenialRecoveryTask {if($script:case -eq 'stop'){throw 'FIXTURE_STOP'};$script:stopped++}
function Start-Sleep {}
function Write-Progress {}
function Read-BoundedJson {param($Path) if($Path.EndsWith('control.json')){return @{mode='LOCKED'}};$v=New-Sample;$script:sequence++;$v.sequence=$script:sequence;return $v}
foreach($script:case in @('valid','preflight','guard','changed','start','wildcard','stop')){
 $script:preflights=0;$script:enabled=0;$script:guardRegistered=0;$script:guardRemoved=0;$script:stopped=0;$script:sequence=1
 $ctx=New-CollectorGatewayContext ('a'*32);$failed=$false;$cleanupFailed=$false
 try{& ([scriptblock]::Create($startSource)) $ctx}catch{$failed=$true}finally{try{Stop-CollectorGatewayWindow $ctx}catch{$cleanupFailed=$true}}
 if($failed -ne ($case -notin @('valid','stop')) -or $cleanupFailed -ne ($case -in @('stop','guard'))){throw "Workflow failed: $case"}
 if($case -in @('preflight','guard','changed') -and $enabled){throw 'Started despite failed preflight/guard'}
 if($case -in @('valid','start','wildcard') -and ($stopped -ne 1 -or $guardRemoved -ne 1)){throw 'Failed to stop and remove guard'}
 if($case -eq 'stop' -and $guardRemoved){throw 'Removed independent guard before confirmed stop'}
}
Write-Host 'COLLECTOR_GATEWAY_WINDOW_FIXTURES_PASSED: 8 readiness cases; 7 startup/cleanup workflows; no real task or network changes.'

# Real atomic summary replacement; export only selected worker fields.
function Assert-TimeObservationAcl {}
function Test-Path {param($LiteralPath) Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-collector-summary-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
$full=Join-Path $temp 'full.json';[IO.File]::WriteAllText($full,'{}')
$save=(Get-Command Save-CollectorAutomaticSummary).ScriptBlock.ToString().Replace('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1',$temp)
foreach($status in @('REVIEW_REQUIRED','HEALTH_COLLECTOR_THREE_ROUNDS_PASSED_REVOKED_LIFECYCLE_PENDING')){
 $report=@{runId=('a'*32);status=$status;worker=@{secret='DO_NOT_EXPORT';finalHealthRevoked=($status -ne 'REVIEW_REQUIRED');collectorRounds=@(@{accepted=$true;healthySubmitted=$true;findings=@()})}}
 & ([scriptblock]::Create($save)) $report $full @{startAttempted=$true;stopped=$true;guardRemoved=$true}
 $text=[IO.File]::ReadAllText((Join-Path $temp 'collector-batch-result.json'));$v=$text|ConvertFrom-Json
 if($text.Contains('DO_NOT_EXPORT') -or $v.status -ne $status -or $v.worker.rounds.Count -ne 1 -or -not $v.gatewayStopped -or $v.ordersEnabled){throw 'Summary invalid or leaked unselected field'}
}
Write-Host 'COLLECTOR_AUTOMATIC_SUMMARY_PASSED: create/replace, failure retention and selected-field export.'
