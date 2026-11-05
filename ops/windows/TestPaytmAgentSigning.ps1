#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmAgentSigning.ps1')
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-agent-signing-'+[guid]::NewGuid().ToString('N'))
$checks=0;$mode='pass';$id='ea8b91471cf048aa97a0f6b939b355c7';$instance='c066052a24f1456895792ee98dda78ac'
function Check($Ok,$Name){if(-not $Ok){throw "AGENT_SIGNING_TEST_$Name"};$script:checks++}
function Reject([scriptblock]$Action,$Name){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad $Name}
function Assert-PaytmAccountPath($Path){$Path}
function Get-PaytmHostContract {@{root=$tmp;work=$tmp;name='fixture-supervisor'}}
function Get-PaytmProbeTask($Name){if($mode -eq 'missingTask'){return};@{State=if($mode -eq 'running'){'Running'}else{'Ready'}}}
function Assert-PaytmHostTask($Task,$InstallationId,$Enabled){Check ($InstallationId -ceq $id -and $Enabled) 'EXACT_TASK_IDENTITY';if($mode -eq 'taskDrift'){throw 'HOST_TASK_PRINCIPAL'}}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) @{LastTaskResult=if($mode -eq 'resultChanged'){0}else{1};LastRunTime=[DateTime]::Parse('2026-11-05T15:47:47Z')}}
function Get-Process {param($ErrorAction) if($mode -eq 'oldProcess'){@{Id=13636}}else{@{Id=99}}}
$receipt=Join-Path $tmp 'review.json'
function Get-FileHash {
 param($LiteralPath,$ErrorAction)
 if($LiteralPath -eq $receipt){@{Hash=if($mode -eq 'receiptHash'){'0'*64}else{'097FE3F105F7579DF20BDC9DE1F5603B43AABF16CC523C5A97026A5E600032D4'}}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -ErrorAction Stop}
}
try{
 $null=New-Item -ItemType Directory -Path $tmp
 foreach($n in @('manifest.json','transport-control.json','session-checkpoint.json','startup-failure.json','status.json')){Write-PaytmHostJson (Join-Path $tmp $n) @{fixture=$true}}
 Write-PaytmHostJson (Join-Path $tmp 'control.json') @{installationId=$id;mode='LOCKED'}
 Write-PaytmHostJson (Join-Path $tmp 'blocked.json') @{instanceId=$instance;failure='HOST_AGENT_UNAVAILABLE'}
 $a=Get-PaytmAgentSigningSnapshot;$b=Get-PaytmAgentSigningSnapshot
 Check ($a.hashes.Count -eq 7 -and ($a|ConvertTo-Json -Depth 5 -Compress) -ceq ($b|ConvertTo-Json -Depth 5 -Compress)) 'SEVEN_UNCHANGED_FILES'
 foreach($mode in @('missingTask','running','taskDrift','resultChanged','oldProcess')){Reject {Get-PaytmAgentSigningSnapshot} $mode}
 $mode='pass'
 Write-PaytmHostJson (Join-Path $tmp 'control.json') @{installationId=$id;mode='UNLOCKED'}
 Reject {Get-PaytmAgentSigningSnapshot} 'UNLOCKED_REJECTED'
 Write-PaytmHostJson (Join-Path $tmp 'control.json') @{installationId=$id;mode='LOCKED'}
 Write-PaytmHostJson (Join-Path $tmp 'blocked.json') @{instanceId='different';failure='HOST_AGENT_UNAVAILABLE'}
 Reject {Get-PaytmAgentSigningSnapshot} 'OTHER_WORKER_REJECTED'
 Write-PaytmHostJson (Join-Path $tmp 'blocked.json') @{instanceId=$instance;failure='HOST_AGENT_UNAVAILABLE'}
 Write-PaytmHostJson (Join-Path $tmp 'session-checkpoint.json') @{changed=$true}
 $b=Get-PaytmAgentSigningSnapshot
 Check ($a.hashes.'session-checkpoint.json' -cne $b.hashes.'session-checkpoint.json') 'CHECKPOINT_BYTE_DRIFT_VISIBLE'
 $r=@{runId='d1938ba2c01d4a1b9759e2b81d972fed';status='AGENT_EVIDENCE_CAPTURED_GATEWAY_RECOVERY_PENDING';failure=$null;checkpointUnchanged=$true;serviceQueriesComplete=$true;checkpointAfter=@{sha256=('A'*64)}}
 Write-PaytmHostJson $receipt $r
 $v=Assert-PaytmAgentSigningReceipt $receipt
 Check ($v.checkpointHash -ceq ('A'*64) -and -not $v.historicalCauseEstablished) 'REVIEWED_RECEIPT'
 $mode='receiptHash';Reject {Assert-PaytmAgentSigningReceipt $receipt} 'WRONG_RECEIPT_HASH';$mode='pass'
 $r.checkpointUnchanged=$false;Write-PaytmHostJson $receipt $r
 Reject {Assert-PaytmAgentSigningReceipt $receipt} 'FAILED_RECEIPT'
 [pscustomobject]@{status='AGENT_SIGNING_PRESERVATION_PASSED';assertions=$checks;productionApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-agent-signing-[a-f0-9]{32}$'){throw 'UNSAFE_AGENT_SIGNING_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
