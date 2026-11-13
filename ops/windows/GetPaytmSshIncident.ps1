#Requires -Version 7.0
[CmdletBinding()]param(
 [ValidateSet('Prepare','Collect')][string]$Phase='Prepare',
 [string]$RecoveryReportPath='C:\MarketBrainData\Review\paytm-native-recovery-ba7938fb742c4ac8bc289a2dcd2ff175.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
if($Phase -eq 'Prepare'){
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../linux/CollectPaytmSshIncident.py'))
 Set-Clipboard -Value ("sudo -n python3 <<'MB_SSH_INCIDENT'`n"+$source.Replace("`r`n","`n")+"`nMB_SSH_INCIDENT`n")
 Write-Host '[20%] VPS read-only command copied. In admin PuTTY run sudo -v, then paste. No START/STOP answer is needed.'
 Write-Host 'Copy the complete BEGIN_PAYTM_SSH_INCIDENT through END_PAYTM_SSH_INCIDENT output block; then run this script with -Phase Collect in PowerShell.'
 return
}
$watch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;gatewayChanged=$false;taskStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;historicalCauseEstablished=$false;exactConnectionMatchEstablished=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$destination=Join-Path $OutputDirectory ('paytm-ssh-incident-'+$report.runId+'.json')
try{
 Write-Host '[40%] Validate saved recovery receipt and decode VPS metadata.'
 $report.sourceHashes=@{}
 foreach($name in @('GetPaytmSshIncident.ps1','../linux/CollectPaytmSshIncident.py')){
  $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
 }
 $hash=(Get-FileHash -LiteralPath $RecoveryReportPath).Hash
 if($hash -cne 'BA07CFC8C9A870B74906BE5286F099370A3FCDD52EA237B8CB43446DECBA88A0'){throw 'INCIDENT_RECEIPT_MISMATCH'}
 $report.recoverySha256=$hash
 $saved=Get-Content -LiteralPath $RecoveryReportPath -Raw | ConvertFrom-Json
 $clip=Get-Clipboard -Raw
 if($clip.Length -gt 2000000){throw 'INCIDENT_CLIPBOARD_OVERSIZE'}
 if($clip -notmatch '(?s)\ABEGIN_PAYTM_SSH_INCIDENT\s+([A-Za-z0-9+/=\s]+)\s+END_PAYTM_SSH_INCIDENT\s*\z'){throw 'INCIDENT_COPY_COMPLETE_BLOCK'}
 $server=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($Matches[1] -replace '\s',''))) | ConvertFrom-Json
 if($server.kind -cne 'PAYTM_SSH_INCIDENT_V1' -or $server.version -ne 1 -or $server.readOnly -ne $true -or $server.since -cne '2026-11-13 13:30:00 UTC' -or $server.until -cne '2026-11-13 13:35:00 UTC'){throw 'INCIDENT_SERVER_REPORT_MISMATCH'}
 $report.server=$server
 $report.windows=@{initial=$saved.nativeRecovery.first;failure=$saved.workerDiagnostics.files.'status.json'.value;failureStopVerified=$saved.failureStopVerified;accountPreserved=$saved.accountPreserved;finalApplicationLockVerified=$saved.finalApplicationLockVerified}
 $report.limitations=@('Historical logs may be rotated or incomplete.','Server PID groups SSH events; Windows report lacks client source port for exact connection matching.','Clock offset at incident time is unknown; do not match by timestamp alone.','A successful key login does not establish successful forwarding or TLS recovery.')
 if($server.success -ne $true){throw 'INCIDENT_SERVER_COLLECTION_INCOMPLETE'}
 $report.status='SSH_INCIDENT_CAPTURED_REVIEW_REQUIRED'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^INCIDENT_[A-Z_]+$'){$_.Exception.Message}else{'INCIDENT_COLLECTION_FAILED'}
 $report.failureType=$_.Exception.GetBaseException().GetType().Name
}finally{
 $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
 $report | ConvertTo-Json -Depth 35 | Set-Content -LiteralPath $destination -Encoding utf8
 Write-Host "[100%] $($report.status). Share this ONE file: $destination"
}
if($report.failure){throw 'Collection incomplete; share the JSON. No gateway state was changed.'}
