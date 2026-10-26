#Requires -Version 5.1
# Installed as protected source; invoked in a dedicated, visible, credentialed console.
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmGateway\key-custody'
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\library.ps1')))
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\native.ps1')))
$plan=([IO.File]::ReadAllText($root+'\plan.json')|ConvertFrom-Json)
if($plan.runId -cnotmatch '^[a-f0-9]{32}$' -or $plan.sid -cne (Get-PaytmKeyContract).accountSid){throw 'KEY_WORKER_PLAN'}
$resultPath='C:\ProgramData\MarketBrainPaytmGateway\work\key-custody-'+$plan.runId+'.json'
$report=[ordered]@{version=1;runId=$plan.runId;stage='IDENTITY';identityVerified=$false;importAttempted=$false;imported=$false;
    revocationVerified=$false;reloadVerified=$false;vpsContactAttempted=$false;wrongHostRejected=$false;pinnedAuthentication=$false;
    authenticationSeconds=$null;wrongHostOutcome=$null;authenticationOutcome=$null;failure=$null;nativeErrorCode=$null;elapsedSeconds=0}
$stream=$null;$timer=[Diagnostics.Stopwatch]::StartNew()
function Save-KeyWorker {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $data=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Compress))
    $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
}
try{
    $Host.UI.RawUI.WindowTitle='MarketBrain GATEWAY KEY — two SSH-key passphrase prompts'
    $stream=[IO.File]::Open($resultPath,'CreateNew','Write','Read');Save-KeyWorker
    Invoke-PaytmCustodySequence $plan $report {Save-KeyWorker}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^KEY_[A-Z_]+$'){$_.Exception.Message}else{'KEY_WORKER_FAILED'}
    $base=$_.Exception.GetBaseException();if($base -is [ComponentModel.Win32Exception]){$report.nativeErrorCode=$base.NativeErrorCode}
}finally{
    $timer.Stop();if($null -ne $stream){try{Save-KeyWorker}finally{$stream.Dispose()}}
    Write-Host 'KEY WINDOW finished. Return to the original PowerShell window for the final report. Do not rerun or remove keys manually.'
}
if($report.failure){exit 1}else{exit 0}
