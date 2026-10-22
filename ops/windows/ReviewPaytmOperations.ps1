#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory=$true)][string]$ApplicationEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsReview.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;startedUtc=[DateTimeOffset]::UtcNow.ToString('o');status='REVIEW_REQUIRED';scope='READ_ONLY_VPS_OPERATIONS_SNAPSHOT';acceptedApplicationEvidence=$null;observations=$null;failure=$null;elapsedSeconds=0;brokerCredentialsUsed=$false;applicationChanged=$false;proxyStarted=$false;settingsChanged=$false;ordersEnabled=$false;unattendedOperationApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ("paytm-operations-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$run)
try {
    Write-Progress -Activity 'Paytm operations review' -Status 'Validate accepted application evidence' -PercentComplete 10
    Write-Host '[10%] Read-only VPS snapshot. No rebuild, restart, proxy start, broker login or trading.'
    $report.acceptedApplicationEvidence=Assert-PaytmAcceptedApplicationReport $ApplicationEvidencePath
    $report.windowsSshInventory=Get-PaytmWindowsSshInventory
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\InspectPaytmOperations.sh'))
    $payload=New-PaytmOperationsPayload $run $source
    $digest=[Security.Cryptography.SHA256]::Create()
    try {$report.payloadSha256=[BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))).Replace('-','')}finally{$digest.Dispose()}
    $null=Read-Host 'Open the verified marketbrain-admin PuTTY session. Run sudo -v there and enter your sudo password. Press Enter HERE once ready'
    $start=[DateTimeOffset]::UtcNow
    Set-Clipboard -Value $payload
    Write-Progress -Activity 'Paytm operations review' -Status 'Waiting for bounded VPS snapshot' -PercentComplete 30
    Write-Host '[30%] Command copied. Paste it into PuTTY. It runs automatically, usually within 60 seconds (180-second outer limit).'
    Write-Host 'Do NOT type START-TEST, STOP, SERVER_READY or load the gateway key. This check has no such prompts.'
    Write-Host "Copy ONLY BEGIN_PAYTM_OPERATIONS_$run through END_PAYTM_OPERATIONS_$run back to the clipboard."
    $null=Read-Host 'Once the complete report block is copied from PuTTY, return HERE and press Enter (within 20 minutes)'
    $received=[DateTimeOffset]::UtcNow
    Write-Progress -Activity 'Paytm operations review' -Status 'Validate current-run evidence' -PercentComplete 80
    Write-Host '[80%] Checking identity, stopped state, public IP, time and cached maintenance evidence.'
    $report.observations=Read-PaytmOperationsReceipt -Text (Get-Clipboard -Raw) -RunId $run -Started $start -Received $received
    $report.status=if($report.observations.findings.Count -eq 0){'SNAPSHOT_CAPTURED_LOGIN_AND_MAINTENANCE_REVIEW_PENDING'}else{'SNAPSHOT_CAPTURED_WITH_FINDINGS'}
} catch {
    # Never echo arbitrary clipboard text or exception payloads into shared evidence.
    $message=$_.Exception.Message
    $report.failure=if($message -cmatch '^OPS_[A-Z_]+$'){$message}else{'OPS_CAPTURE_FAILED_CHECK_LOCAL_PREREQUISITES'}
} finally {
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $json=$report|ConvertTo-Json -Depth 12
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$bytes=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm operations review' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No changes applied. VPS-bound IP is not an application/proxy egress observation; cached updates are not proof of patch currency.'
}
if($report.failure){throw $report.failure}
