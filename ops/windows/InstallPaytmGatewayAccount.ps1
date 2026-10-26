#Requires -Version 7.0
[CmdletBinding()]param([ValidateSet('Apply','Verify','Disable','Recover')][string]$Mode='Apply',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$RecoveryInventoryPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
if($Mode -ceq 'Recover'){. (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1')}
$c=Get-PaytmAccountContract;$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$password=$null;$confirmPassword=$null;$stream=$null
$report=[ordered]@{schemaVersion=1;runId=$run;mode=$Mode;status='REVIEW_REQUIRED';stage='INVENTORY';
    inventory=$null;createdAccount=$false;createdDirectory=$false;accountSid=$null;agentChanged=$false;
    recovery=[ordered]@{approved=$null;archivePath=$null;archiveMoveAttempted=$false;archiveCreated=$false;archiveVerified=$false;manifestHash=$null};
    probe=$null;probeLaunch=[ordered]@{};probeLaunchContract=$null;events=@();passwordAttempts=@();sourceHashes=[ordered]@{};failure=$null;failureDetails=$null;elapsedSeconds=0;
    acceptedProgressAtScriptRelease=@();candidateGroup2PercentIfReviewed=$null;
    sshKeysImported=$false;scheduledTaskInstalled=$false;vpsContacted=$false;gatewayActivated=$false;ordersEnabled=$false}
function Save-AccountCheckpoint {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10))
    $stream.Position=0;$stream.SetLength(0);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
}
function Account-Step([string]$Name,[int]$Percent,[scriptblock]$Action){
    $report.stage=$Name;Save-AccountCheckpoint
    Write-Progress -Activity 'Paytm restricted Windows account' -Status $Name -PercentComplete $Percent
    Write-Host "[$Percent%] $Name"
    $stepTimer=[Diagnostics.Stopwatch]::StartNew()
    & $Action
    $report.events+=@([pscustomobject]@{stage=$Name;completed=$true;elapsedSeconds=[math]::Round($stepTimer.Elapsed.TotalSeconds,3)})
    Save-AccountCheckpoint
}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-gateway-account-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-AccountCheckpoint
    foreach($name in @('InstallPaytmGatewayAccount.ps1','PaytmGatewayAccount.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash}
    if($Mode -ceq 'Recover'){$report.sourceHashes['PaytmGatewayAccountRepair.ps1']=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1') -Algorithm SHA256).Hash}
    $report.acceptedProgressAtScriptRelease=@(Get-PaytmReadinessProgress)
    # Inspect the exact production launch contract before any account/service writes.
    $probeInfo=New-PaytmAccountProbeStartInfo $null
    $report.probeLaunchContract=[pscustomobject]@{transport='UTF8_STDIN';commandLineCharacters=($probeInfo.FileName.Length+$probeInfo.Arguments.Length+4);maximumCommandLineCharacters=1024}
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $null=Assert-PaytmAccountPath $c.root
    $agent=Get-Service ssh-agent -ErrorAction Stop
    if($Mode -ceq 'Recover'){
        $agentRegistry=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ssh-agent' -ErrorAction Stop
        $agentCim=[pscustomobject]@{PathName=$agentRegistry.ImagePath;StartName=$agentRegistry.ObjectName}
    }else{$agentCim=Get-CimInstance Win32_Service -Filter "Name='ssh-agent'" -OperationTimeoutSec 10 -ErrorAction Stop}
    $secondary=Get-Service seclogon -ErrorAction Stop
    $accounts=@(Get-LocalUser -ErrorAction Stop | Where-Object {$_.Name -ieq $c.name})
    $report.inventory=[pscustomobject]@{
        elevated=$elevated;native64Bit=[Environment]::Is64BitProcess;
        toolsPresent=((Test-Path -LiteralPath $c.agentImage -PathType Leaf) -and (Test-Path -LiteralPath 'C:\Windows\System32\OpenSSH\ssh-add.exe' -PathType Leaf) -and (Test-Path -LiteralPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PathType Leaf));
        accountExists=($accounts.Count -gt 0);rootExists=(Test-Path -LiteralPath $c.root);
        agentImage=[string]$agentCim.PathName;agentStartName=[string]$agentCim.StartName;
        agentStatus=[string]$agent.Status;agentStartType=[string]$agent.StartType;
        secondaryLogonStartType=[string]$secondary.StartType;
        agentControlError=if($Mode -ceq 'Apply'){Get-PaytmAgentControlAccess}else{$null}}
    Assert-PaytmAccountInventory $report.inventory $Mode
    $null=@(Get-PaytmLocalMembershipSnapshot) # Local account API preflight; no membership details logged.
    if($Mode -ceq 'Recover'){
        $report.recovery.approved=Read-PaytmReviewedRecovery $RecoveryInventoryPath
        $report.recovery.archivePath=Get-PaytmRepairArchivePath $run
        $null=Assert-PaytmRepairState $report.recovery.approved $report.recovery.archivePath
    }
    Save-AccountCheckpoint
    if($Mode -cin @('Apply','Recover')){
        if($Mode -ceq 'Recover'){
            Write-Host "Recovery: preserve old storage at $($report.recovery.archivePath), create a NEW non-admin account/SID and fresh protected storage, then verify. No files deleted."
            Write-Host 'The already Running/Automatic shared ssh-agent is preserved: no stop, start or configuration changes.'
        }else{Write-Host 'This creates local NON-ADMIN user marketbrain-gateway, protected C:\ProgramData\MarketBrainPaytmGateway, and enables/starts the existing Windows ssh-agent service (system-wide).'}
        Write-Host 'It does NOT install OpenSSH Server, import a key, create a scheduled task, change VPS/firewall/Paytm settings or start a tunnel.'
        Write-Host 'Choose a NEW account password (14+ characters) and keep it in your password manager. Do not enter your VPS/Windows-admin/Paytm password here or share it in chat.'
        Write-Host 'On a partial failure, account/files/service state are preserved and recorded; no blind rollback or deletion. Do not repeat Apply or Recover.'
        $consent=if($Mode -ceq 'Recover'){'RECOVER-ACCOUNT'}else{'PROVISION-ACCOUNT'}
        if((Read-Host "Type $consent to authorize exactly these changes") -cne $consent){throw 'ACCOUNT_OWNER_CANCELLED'}
        $report.stage='PASSWORD_CONFIRMATION';Save-AccountCheckpoint
        Write-Host '[10%] Private password confirmation: up to 3 attempts. No account or service changes have started. Ctrl+C cancels.'
        $passwordAccepted=$false
        for($attempt=1;$attempt -le 3;$attempt++){
            try{
                Write-Host "Password attempt $attempt of 3. Enter the same NEW password twice; check Caps Lock and keyboard layout."
                $password=Read-Host 'New dedicated Windows account password (14+ characters)' -AsSecureString
                $confirmPassword=Read-Host 'Confirm the SAME new account password' -AsSecureString
                $passwordResult=Get-PaytmAccountPasswordResult $password $confirmPassword
                $passwordAccepted=$passwordResult -ceq 'CONFIRMED'
                $report.passwordAttempts+=@([pscustomobject]@{attempt=$attempt;outcome=$passwordResult})
                Save-AccountCheckpoint
            }finally{
                if($null -ne $confirmPassword){$confirmPassword.Dispose();$confirmPassword=$null}
                if(-not $passwordAccepted -and $null -ne $password){$password.Dispose();$password=$null}
            }
            if($passwordAccepted){break}
            switch($passwordResult){
                ACCOUNT_PASSWORD_TOO_SHORT {Write-Host 'The new password must contain at least 14 characters. No changes made.'}
                ACCOUNT_PASSWORD_CONFIRMATION_MISMATCH {Write-Host 'The two password entries did not match exactly. No changes made.'}
                default {Write-Host 'Password input was missing. No changes made.'}
            }
        }
        if(-not $passwordAccepted){throw $passwordResult}
        if($Mode -ceq 'Recover'){
            Account-Step 'PRESERVE_OLD_INSTALLATION' 15 {
                $state=Assert-PaytmRepairState $report.recovery.approved $report.recovery.archivePath
                $report.recovery.manifestHash=$state.manifestHash
                $report.recovery.archiveMoveAttempted=$true;Save-AccountCheckpoint
                Move-PaytmRepairArchive $report.recovery.archivePath $run
                $report.recovery.archiveCreated=$true;Save-AccountCheckpoint
                Assert-PaytmRepairArchive $report.recovery.archivePath $state.manifestHash $report.recovery.approved.oldSid
                $report.recovery.archiveVerified=$true;Save-AccountCheckpoint
            }
        }
        $report.stage='PRE_APPLY_RECHECK';Save-AccountCheckpoint
        # Recheck absence immediately before account creation. Never adopt/reset an existing user.
        if(@(Get-LocalUser | Where-Object {$_.Name -ieq $c.name}).Count -or (Test-Path -LiteralPath $c.root)){throw 'ACCOUNT_TARGET_CHANGED_BEFORE_APPLY'}
        Account-Step 'CREATE_DISABLED_ACCOUNT' 20 {
            $newAccount=New-LocalUser -Name $c.name -Password $password -Description $c.description -Disabled -ErrorAction Stop
            $report.accountSid=$newAccount.SID.Value;$report.createdAccount=$true
            if($Mode -ceq 'Recover' -and $report.accountSid -ceq $report.recovery.approved.oldSid){throw 'ACCOUNT_REPAIR_SID_NOT_NEW'}
        }
        Account-Step 'STANDARD_USER_GROUP' 30 {
            $alreadyMember=@(Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction Stop | Where-Object {$_.SID.Value -ceq $report.accountSid}).Count -gt 0
            if(-not $alreadyMember){Add-LocalGroupMember -SID 'S-1-5-32-545' -Member (Get-LocalUser -SID $report.accountSid) -ErrorAction Stop}
        }
        Account-Step 'PROTECTED_STORAGE_AND_MANIFEST' 45 {
            if(Test-Path -LiteralPath $c.root){throw 'ACCOUNT_STORAGE_COLLISION'}
            $null=New-Item -ItemType Directory -Path $c.root -ErrorAction Stop;$report.createdDirectory=$true
            Set-PaytmAccountDirectoryAcl $c.root $report.accountSid
            $work=Join-Path $c.root 'work';$null=New-Item -ItemType Directory -Path $work -ErrorAction Stop
            Set-PaytmAccountDirectoryAcl $work $report.accountSid -Writable
            Write-PaytmAccountNewJson (Join-Path $c.root 'installation.json') ([ordered]@{
                version=1;runId=$run;name=$c.name;root=$c.root;sid=$report.accountSid;
                previousAgentStatus=$report.inventory.agentStatus;previousAgentStartType=$report.inventory.agentStartType;
                passwordExpiryPolicy='WINDOWS_DEFAULT_UNCHANGED';containsPrivateKey=$false;
                recoveryFrom=if($Mode -ceq 'Recover'){[ordered]@{oldSid=$report.recovery.approved.oldSid;installationRunId=$report.recovery.approved.installationRunId;archivePath=$report.recovery.archivePath;agentConfigurationPreserved=$true}}else{$null}})
            $null=Read-PaytmOwnedAccount
        }
        Account-Step 'ENABLE_RESTRICTED_ACCOUNT' 55 {Enable-LocalUser -SID $report.accountSid -ErrorAction Stop}
        if($Mode -ceq 'Recover'){
            Account-Step 'CONFIRM_SHARED_AGENT_UNCHANGED' 65 {Assert-PaytmRepairAgent}
        }else{Account-Step 'ENABLE_EXISTING_CLIENT_AGENT' 65 {
            # Journal intent first so a failure after Set-Service is not reported as untouched.
            $report.agentChanged=$true;Save-AccountCheckpoint
            Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction Stop
            Start-Service -Name ssh-agent -ErrorAction Stop
            (Get-Service ssh-agent).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
        }}
    }else{
        $saved=Read-PaytmOwnedAccount;$report.accountSid=$saved.sid
        if($Mode -ceq 'Disable'){
            Write-Host 'Containment only: disable the exact owned Windows account. Does not terminate existing sessions, stop shared ssh-agent, remove keys/files or change VPS.'
            if((Read-Host 'Type DISABLE-ACCOUNT to confirm') -cne 'DISABLE-ACCOUNT'){throw 'ACCOUNT_OWNER_CANCELLED'}
            Account-Step 'DISABLE_OWNED_ACCOUNT' 70 {Disable-LocalUser -SID $saved.sid -ErrorAction Stop}
            if((Get-LocalUser -SID $saved.sid).Enabled){throw 'ACCOUNT_DISABLE_NOT_CONFIRMED'}
            $report.status='GATEWAY_ACCOUNT_DISABLED_SHARED_AGENT_UNCHANGED'
        }else{
            Write-Host 'Verify only: preserve the existing account, password, folders and shared agent configuration. Run the private identity/storage/agent probe; no VPS or broker access.'
            $password=Read-Host 'Existing marketbrain-gateway Windows account password (not an admin or VPS password)' -AsSecureString
        }
    }
    if($Mode -cne 'Disable'){
        Account-Step 'POSTCHECK_ACCOUNT_AND_AGENT' 75 {
            $saved=Read-PaytmOwnedAccount
            if(-not (Get-LocalUser -SID $saved.sid).Enabled){throw 'ACCOUNT_NOT_ENABLED'}
            $service=Get-Service ssh-agent
            if($service.Status -ne 'Running' -or $service.StartType -ne 'Automatic'){throw 'ACCOUNT_AGENT_NOT_READY'}
        }
        Account-Step 'EXACT_ACCOUNT_PRIVATE_PROBE' 85 {
            $report.probe=Invoke-PaytmAccountProbe $report.accountSid $run $password $report.probeLaunch
            # Preserve safe child check outcomes before enforcing acceptance.
            Save-AccountCheckpoint
            Assert-PaytmAccountProbe $report.probe $run
        }
        $report.status='GATEWAY_ACCOUNT_PROVISIONED_KEY_CUSTODY_PENDING'
        $report.candidateGroup2PercentIfReviewed=40
    }
    $report.stage='COMPLETE'
}catch{
    $message=$_.Exception.Message
    $report.failure=if($message -cmatch '^ACCOUNT_[A-Z_]+$'){$message}else{'ACCOUNT_SETUP_FAILED'}
    $safeId=if($_.FullyQualifiedErrorId -cmatch '^[A-Za-z0-9_.,:-]{1,200}$'){$_.FullyQualifiedErrorId}else{'REDACTED'}
    $base=$_.Exception.GetBaseException()
    $report.failureDetails=[pscustomobject]@{stage=$report.stage;exceptionType=$_.Exception.GetType().Name;hresult=$_.Exception.HResult;scriptLine=$_.InvocationInfo.ScriptLineNumber;errorId=$safeId;nativeErrorCode=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null}}
}finally{
    if($null -ne $password){$password.Dispose()};if($null -ne $confirmPassword){$confirmPassword.Dispose()}
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    if($null -ne $stream){try{Save-AccountCheckpoint}finally{$stream.Dispose()}}
    Write-Progress -Activity 'Paytm restricted Windows account' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    if($report.recovery.archiveMoveAttempted){Write-Host "Preserved-folder target (do not delete or restore manually): $($report.recovery.archivePath)"}
    Write-Host ('Accepted progress at script release: '+(($report.acceptedProgressAtScriptRelease|ForEach-Object { "$($_.id)=$($_.percent)%" }) -join ', '))
    if($null -ne $report.candidateGroup2PercentIfReviewed){Write-Host "This account result is a candidate for G2=$($report.candidateGroup2PercentIfReviewed)%, pending evidence review."}
    if($report.failure){
        if($report.stage -ceq 'PASSWORD_CONFIRMATION'){
            Write-Host "Stopped before account/service/storage changes. You may run the same $Mode command again later; it rechecks its required baseline. Do not delete anything. Share only the JSON, never passwords."
        }else{Write-Host 'STOP: do not rerun Apply/Recover or delete the account/folder. Share the JSON; it records completed and possibly partial steps.'}
    }
}
if($report.failure){throw $report.failure}
