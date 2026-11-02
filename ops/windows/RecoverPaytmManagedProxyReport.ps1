#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$FailedReportPath='C:\MarketBrainData\Review\paytm-managed-proxy-20261102-231326-25659b497afb4d088bf9fbf309f791b1.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedProxy.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedProxyRecovery.ps1')
$clock=[Diagnostics.Stopwatch]::StartNew()
$r=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;failureDetails=$null;sourceHashes=@{};elapsedSeconds=0;originalRunId=$null;sourceReceiptHash=$null;recoveryEnvelope=$null;recovered=$null;server=$null;parseFailure=$null;installationRepeated=$false;serviceChanged=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-managed-report-recovery-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$r.runId+'.json')
function Save-Recovery {$r.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3);[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
$stream=[IO.File]::Open($path,'CreateNew','Write','Read');$stream.Dispose()
try{
 $r.sourceReceiptHash=(Get-FileHash -LiteralPath $FailedReportPath).Hash
 if($r.sourceReceiptHash -cne '485EEFFBAC25692488BDF641226BE5CD865BCBD76B1170F5B274F845042ABBFC'){throw 'RECOVERY_RECEIPT_NOT_REVIEWED'}
 $r.originalRunId='25659b497afb4d088bf9fbf309f791b1';Save-Recovery
 foreach($name in @('RecoverPaytmManagedProxyReport.ps1','PaytmManagedProxyRecovery.ps1','PaytmManagedProxy.ps1','PaytmTunnelVerification.ps1','..\linux\ReadPaytmManagedProxyReport.sh')){$r.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 Set-Clipboard -Value (Get-PaytmManagedRecoveryPayload $r.originalRunId $r.runId)
 Write-Host '[20%] Read-only VPS command copied. In verified admin PuTTY run sudo -v, then paste the copied command.'
 Write-Host 'No installation or service changes. Copy BEGIN_MANAGED_RECOVERY through END_MANAGED_RECOVERY after it finishes.'
 Write-Progress -Activity 'Recover managed proxy evidence' -Status 'Waiting for read-only VPS capture' -PercentComplete 20
 if((Read-Host 'After copying the complete recovery block, type REPORT-COPIED here') -cne 'REPORT-COPIED'){throw 'RECOVERY_COPY_NOT_CONFIRMED'}
 $text=Get-Clipboard -Raw
 if($text.Length -gt 65536){throw 'RECOVERY_REPORT_TOO_LARGE'}
 $m=[regex]::Match($text,'(?ms)^BEGIN_MANAGED_RECOVERY_'+$r.runId+'\r?\n.*?^END_MANAGED_RECOVERY_'+$r.runId+'\r?$')
 if($m.Success){$r.recoveryEnvelope=$m.Value;Save-Recovery}
 $r.recovered=Read-PaytmManagedRecoveryReport $text $r.originalRunId $r.runId;Save-Recovery
 try{$r.server=Read-PaytmManagedProxyReport $r.recovered.originalReport $r.originalRunId}catch{$r.parseFailure=$_.Exception.Message}
 $r.status='EVIDENCE_RECOVERED_REVIEW_REQUIRED'
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(RECOVERY|MANAGED)_[A-Z_]+$'){$_.Exception.Message}else{'RECOVERY_COLLECTION_FAILED'}
 $r.failureDetails=[ordered]@{exceptionType=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName);line=$_.InvocationInfo.ScriptLineNumber}
}finally{
 Save-Recovery;Write-Progress -Activity 'Recover managed proxy evidence' -Completed
 Write-Host "[100%] $($r.status); elapsed=$($r.elapsedSeconds)s"
 Write-Host "Share this ONE file: $path"
 Write-Host 'Do not rerun the managed installer. This capture does not approve or change the VPS state.'
}
if($r.failure){throw $r.failure}
