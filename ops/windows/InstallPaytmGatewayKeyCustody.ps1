#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory)][string]$EncryptedKeyPath,
    [string]$AccountReportPath='C:\MarketBrainData\Review\paytm-gateway-account-20261026-220639-ed64356fd5d84c02b0c156f1fc3ef1b4.json',
    [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$c=Get-PaytmKeyContract;$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$password=$null;$bytes=$null;$stream=$null;$window=$null;$windowStarted=$false;$privateHash=$null
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;
    acceptedAccountRun=$c.accountRun;accountSid=$c.accountSid;sourceHashes=[ordered]@{};input=$null;hostPin=$null;hostScan=$null;
    stagingCreated=$false;stagedEncryptedCopyRemoved=$false;operatorSigningDeniedBefore=$false;operatorSigningDeniedAfter=$false;
    emptyAgentProbe=$null;worker=$null;workerExit=$null;windowStopConfirmed=$null;freshProcess=$null;
    events=@();elapsedSeconds=0;acceptedProgressAtScriptRelease=@();candidateGroup2PercentIfReviewed=$null;
    privateKeyContentsLogged=$false;vpsContactAttempted=$false;serviceConfigurationChanged=$false;
    taskInstalled=$false;tunnelStarted=$false;proxyStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;
    rebootPersistenceTested=$false;unrelatedStandardUserTested=$false;serverRestrictionPolicyRetested=$false}
function Save-KeyCheckpoint {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $data=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12))
    $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
}
function Key-Step([string]$Name,[int]$Percent,[scriptblock]$Action) {
    $report.stage=$Name;Save-KeyCheckpoint;Write-Progress -Activity 'Gateway key custody' -Status $Name -PercentComplete $Percent
    Write-Host "[$Percent%] $Name";$clock=[Diagnostics.Stopwatch]::StartNew();&$Action
    $report.events+=@([pscustomobject]@{stage=$Name;elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3)});Save-KeyCheckpoint
}
function Write-KeyNewFile([string]$Path,[byte[]]$Data) {
    $null=Assert-PaytmAccountPath $Path;$f=[IO.File]::Open($Path,'CreateNew','Write','None')
    try{$f.Write($Data,0,$Data.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Read-KeyWorkerReport([string]$Path) {
    $value=Read-PaytmRepairJson $Path 16384
    if($value.version -ne 1 -or $value.runId -cne $run){throw 'KEY_WORKER_REPORT_BINDING'};$value
}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-key-custody-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-KeyCheckpoint
    foreach($file in @('InstallPaytmGatewayKeyCustody.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayKeyWorker.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmTunnelVerification.ps1')){
        $report.sourceHashes[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file)).Hash
    }
    $report.acceptedProgressAtScriptRelease=@(Get-PaytmReadinessProgress)
    Assert-PaytmCustodyController
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $null=Assert-PaytmAccountPath $AccountReportPath
    if((Get-FileHash -LiteralPath $AccountReportPath).Hash -cne 'C4C78B0B4339E41A0CE17087D70F55D887440F7D93182E484AD115A0901F4912'){throw 'KEY_ACCOUNT_REPORT_NOT_ACCEPTED'}
    $saved=Read-PaytmOwnedAccount
    if($saved.sid -cne $c.accountSid -or $saved.runId -cne $c.accountRun -or -not (Get-LocalUser -SID $saved.sid).Enabled){throw 'KEY_ACCOUNT_CHANGED'}
    Assert-PaytmRepairAgent
    foreach($exe in @('ssh.exe','ssh-add.exe','ssh-keyscan.exe')){if(-not (Test-Path -LiteralPath ('C:\Windows\System32\OpenSSH\'+$exe) -PathType Leaf)){throw 'KEY_CLIENT_MISSING'}}
    $null=Assert-PaytmAccountPath $c.root
    if(Test-Path -LiteralPath $c.root){throw 'KEY_STAGING_ALREADY_EXISTS_REVIEW_REQUIRED'}
    $inputPath=Assert-PaytmAccountPath $EncryptedKeyPath
    if($inputPath -notmatch '^[A-Za-z]:\\' -or $inputPath.StartsWith([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $inputPath.StartsWith('C:\ProgramData\MarketBrainPaytmGateway\',[StringComparison]::OrdinalIgnoreCase)){throw 'KEY_PRIVATE_INPUT_LOCATION'}
    $file=[IO.File]::Open($inputPath,'Open','Read','Read')
    try{
        if($file.Length -gt 16384 -or $file.Length -lt 100){throw 'KEY_INPUT_SIZE'}
        $bytes=[byte[]]::new([int]$file.Length);$read=0
        while($read -lt $bytes.Length){$n=$file.Read($bytes,$read,$bytes.Length-$read);if($n -le 0){throw 'KEY_INPUT_TRUNCATED'};$read+=$n}
    }finally{$file.Dispose()}
    $report.input=Assert-PaytmEncryptedKey $bytes
    $null=New-PaytmCustodyWindowInfo $null
    Write-Host 'One-time custody: stage an encrypted copy, open a dedicated gateway-account window, import/revoke/reimport ONLY the approved key, and make bounded pinned SSH authentication tests.'
    Write-Host 'No tunnel/listener, VPS proxy activation, service/task change, broker credential, or trade. Original encrypted export and PPK remain untouched.'
    Write-Host 'After successful worker verification, only the staged encrypted copy is removed; a fresh-process test must then sign using the agent alone.'
    Write-Host 'A visible KEY WINDOW will request the SSH-key passphrase TWICE. Do not start a transcript or share private files. Partial key state is preserved on failure; no blind retry.'
    if((Read-Host 'Type IMPORT-GATEWAY-KEY to authorize this batch') -cne 'IMPORT-GATEWAY-KEY'){throw 'KEY_OWNER_CANCELLED'}
    $password=Read-Host 'Existing WINDOWS marketbrain-gateway account password (not the SSH-key passphrase)' -AsSecureString
    Key-Step 'EXACT_ACCOUNT_EMPTY_AGENT' 10 {
        $diag=[ordered]@{};$report.emptyAgentProbe=Invoke-PaytmAccountProbe $c.accountSid $run $password $diag
        Assert-PaytmAccountProbe $report.emptyAgentProbe $run
    }
    Key-Step 'VERIFY_EXISTING_HOST_PIN' 20 {
        $report.vpsContactAttempted=$true;Save-KeyCheckpoint
        $scan=Invoke-PaytmCustodyNative 'ssh-keyscan.exe' @('-v','-4','-T','5','-t','rsa',$c.hostAddress) 10
        $report.hostScan=Get-PaytmHostScanEvidence $scan;Save-KeyCheckpoint
        if($scan.StoppedByRunner -or $scan.ExitCode -ne 0){throw 'KEY_HOST_SCAN_FAILED'}
        $script:pins=ConvertTo-PaytmPinnedHost $scan.Stdout;$report.hostPin=$pins.fingerprint
    }
    Key-Step 'PROTECTED_STAGING' 30 {
        # Fresh absence/ownership checks before mutation. Never adopt or replace a previous custody attempt.
        $again=Read-PaytmOwnedAccount;if($again.sid -cne $c.accountSid -or $again.runId -cne $c.accountRun){throw 'KEY_ACCOUNT_CHANGED'}
        Assert-PaytmRepairAgent;$null=Assert-PaytmAccountPath $c.root
        if(Test-Path -LiteralPath $c.root){throw 'KEY_STAGING_ALREADY_EXISTS_REVIEW_REQUIRED'}
        $null=New-Item -ItemType Directory -Path $c.root;$report.stagingCreated=$true;Save-KeyCheckpoint
        Set-PaytmAccountDirectoryAcl $c.root $c.accountSid
        foreach($pair in @(@('PaytmGatewayKeyCustody.ps1','library.ps1'),@('PaytmGatewayKeyWorker.ps1','worker.ps1'),@('PaytmTunnelVerification.ps1','native.ps1'))){
            Write-KeyNewFile (Join-Path $c.root $pair[1]) ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $pair[0])))
            if((Get-FileHash -LiteralPath (Join-Path $c.root $pair[1])).Hash -cne $report.sourceHashes[$pair[0]]){throw 'KEY_WORKER_SOURCE_CHANGED'}
        }
        Write-KeyNewFile (Join-Path $c.root 'gateway.pub') ([Text.Encoding]::ASCII.GetBytes(('ssh-ed25519 '+$c.publicBlob+"`n")))
        Write-KeyNewFile (Join-Path $c.root 'known_hosts') ([Text.Encoding]::ASCII.GetBytes($pins.knownHost))
        Write-KeyNewFile (Join-Path $c.root 'wrong_hosts') ([Text.Encoding]::ASCII.GetBytes($pins.wrongHost))
        Write-PaytmAccountNewJson (Join-Path $c.root 'plan.json') ([ordered]@{runId=$run;sid=$c.accountSid})
        $private=Join-Path $c.root 'gateway.openssh';Write-KeyNewFile $private $bytes
        Set-PaytmPrivateKeyAcl $private $c.accountSid
        $script:privateHash=(Get-FileHash -LiteralPath $private).Hash
        Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',(Join-Path $c.root 'gateway.pub'))) $false
        $report.operatorSigningDeniedBefore=$true
    }
    $childReport=Join-Path (Join-Path (Get-PaytmAccountContract).root 'work') ('key-custody-'+$run+'.json')
    Key-Step 'INTERACTIVE_GATEWAY_KEY_WINDOW' 40 {
        $null=Assert-PaytmAccountPath $childReport;if(Test-Path -LiteralPath $childReport){throw 'KEY_REPORT_COLLISION'}
        $script:window=New-PaytmCustodyProcess;$window.StartInfo=New-PaytmCustodyWindowInfo $password
        Write-Host 'NOW switch to the new GATEWAY KEY window. Enter the SSH-key passphrase there at BOTH prompts. This original window needs no input until completion.'
        $script:windowStarted=$window.Start();if(-not $windowStarted){throw 'KEY_WINDOW_START_FAILED'}
        $wait=[Diagnostics.Stopwatch]::StartNew()
        while(-not $window.WaitForExit(1000)){
            if($wait.Elapsed.TotalSeconds -gt 480){throw 'KEY_WINDOW_TIMEOUT'}
            Write-Progress -Activity 'Gateway key custody' -Status ('Waiting for KEY WINDOW; elapsed {0:n0}s / 480s limit' -f $wait.Elapsed.TotalSeconds) -PercentComplete 50
        }
        $report.workerExit=$window.ExitCode;$report.windowStopConfirmed=$true
        $report.worker=Read-KeyWorkerReport $childReport;Save-KeyCheckpoint
        if($window.ExitCode -ne 0 -or $report.worker.stage -cne 'COMPLETE' -or $null -ne $report.worker.failure){throw 'KEY_WORKER_DID_NOT_PASS'}
        foreach($field in @('identityVerified','importAttempted','imported','revocationVerified','reloadVerified','wrongHostRejected','pinnedAuthentication')){
            if($report.worker.$field -isnot [bool] -or -not $report.worker.$field){throw 'KEY_WORKER_CHECK_NOT_PASSED'}
        }
    }
    Key-Step 'REMOVE_OWNED_ENCRYPTED_STAGING_COPY' 75 {
        $private=Assert-PaytmAccountPath (Join-Path $c.root 'gateway.openssh')
        if((Get-FileHash -LiteralPath $private).Hash -cne $privateHash){throw 'KEY_STAGED_COPY_CHANGED'}
        # Only the exact encrypted copy created by this run is removed; original export/PPK are untouched.
        [IO.File]::Delete($private);$report.stagedEncryptedCopyRemoved=$true
    }
    Key-Step 'FRESH_ACCOUNT_PROCESS_AND_OPERATOR_ISOLATION' 85 {
        $info=New-PaytmAccountProbeStartInfo $password;$diag=[ordered]@{}
        try{$report.freshProcess=Invoke-PaytmAccountProbeProcess $info (New-PaytmCustodyFreshSource $run) $diag}finally{$info.Password=$null}
        Save-KeyCheckpoint
        if($report.freshProcess.runId -cne $run -or $null -ne $report.freshProcess.failure){throw 'KEY_FRESH_PROCESS_FAILED'}
        foreach($field in @('identityVerified','agentIdentityVerified','signingVerified')){if($report.freshProcess.$field -isnot [bool] -or -not $report.freshProcess.$field){throw 'KEY_FRESH_PROCESS_FAILED'}}
        Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',(Join-Path $c.root 'gateway.pub'))) $false
        $report.operatorSigningDeniedAfter=$true
    }
    Write-PaytmAccountNewJson (Join-Path $c.root 'custody-state.json') ([ordered]@{version=1;runId=$run;sid=$c.accountSid;fingerprint=$c.fingerprint;hostPin=$c.hostPin;privateFileRetained=$false;taskInstalled=$false})
    $report.status='GATEWAY_KEY_CUSTODY_AND_AUTH_PASSED_LIFECYCLE_PENDING';$report.stage='COMPLETE';$report.candidateGroup2PercentIfReviewed=60
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'KEY_CUSTODY_FAILED'}
    $base=$_.Exception.GetBaseException();$report.failureDetails=[pscustomobject]@{type=$_.Exception.GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;nativeError=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null}}
}finally{
    if($null -ne $window){
        try{if($windowStarted -and -not $window.HasExited){$window.Kill($true);$report.windowStopConfirmed=$window.WaitForExit(5000)}}catch{$report.windowStopConfirmed=$false;$report.failure='KEY_WINDOW_STOP_FAILED';$report.status='REVIEW_REQUIRED'}
        finally{$window.StartInfo.Password=$null;$window.Dispose()}
    }
    if($report.stagingCreated -and $null -eq $report.worker -and $null -ne $childReport -and (Test-Path -LiteralPath $childReport)){
        try{$report.worker=Read-KeyWorkerReport $childReport}catch{} # Preserve safe partial output; never infer import absence.
    }
    if($null -ne $password){$password.Dispose()};if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}
    $timer.Stop();if($null -ne $stream){try{Save-KeyCheckpoint}finally{$stream.Dispose()}}
    Write-Progress -Activity 'Gateway key custody' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    if($report.stagedEncryptedCopyRemoved){Write-Host 'Removed only this run staged encrypted copy. Your original encrypted export and PPK remain available.'}
    if($report.failure){
        if($report.stagingCreated){Write-Host 'STOP: keep the report and protected staging. Do not rerun, reset the account, clear agent keys or change the VPS. A key may already be loaded.'}
        else{Write-Host 'Stopped before key staging/import. Share the report for review; no account reset or key removal is needed.'}
    }
    else{Write-Host 'Candidate G2=60% after evidence review. No scheduled task, tunnel, proxy, broker login or trade was activated.'}
}
if($report.failure){throw $report.failure}
