#Requires -Version 7.0
[CmdletBinding()]param([ValidateSet('Apply','Verify')][string]$Mode='Apply',
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-login-d2ae8a85fc4c4e389fd15bd0a30abb0c.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmGatewayAccount.ps1"
. "$PSScriptRoot/PaytmHealthAccount.ps1"
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$confirm=$null
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory "paytm-health-account-$run.json"
$report=[ordered]@{version=1;runId=$run;mode=$Mode;stage='PREFLIGHT';status='REVIEW_REQUIRED';failure=$null;failureDetails=$null;createdAccount=$false;createdDirectory=$false;accountSid=$null;probe=$null;probeLaunch=@{};sourceHashes=@{};elapsedSeconds=0;agentChanged=$false;privateKeyImported=$false;taskInstalled=$false;ordersEnabled=$false}
function Save-HealthAccount {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 8))}
try{
 Save-HealthAccount
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '5D68A3E08148C8409767B1C1A670E02817395100B5301D886120695D4D77ADEF'){throw 'HEALTH_ACCOUNT_EVIDENCE_MISMATCH'}
 foreach($n in @('InstallPaytmHealthAccount.ps1','PaytmHealthAccount.ps1','PaytmGatewayAccount.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath "$PSScriptRoot/$n").Hash}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not [Environment]::Is64BitProcess -or -not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'HEALTH_ACCOUNT_ELEVATED_64BIT_REQUIRED'}
 Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 foreach($tool in @('C:\Windows\System32\OpenSSH\ssh-add.exe','C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')){if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){throw 'HEALTH_ACCOUNT_TOOL_MISSING'}}
 $c=Get-PaytmHealthAccountContract;$null=Assert-PaytmAccountPath $c.root
 $agent=Get-Service ssh-agent -ErrorAction Stop
 if($agent.Status -ne 'Running' -or $agent.StartType -ne 'Automatic'){throw 'HEALTH_ACCOUNT_AGENT_NOT_READY'}
 if((Get-Service seclogon -ErrorAction Stop).StartType -eq 'Disabled'){throw 'HEALTH_ACCOUNT_SECONDARY_LOGON_DISABLED'}
 $null=@(Get-PaytmLocalMembershipSnapshot)
 if($Mode -eq 'Apply' -and (@(Get-LocalUser|Where-Object {$_.Name -ieq $c.name}).Count -or (Test-Path -LiteralPath $c.root))){throw 'HEALTH_ACCOUNT_TARGET_EXISTS'}
 if($Mode -eq 'Verify'){$null=Read-PaytmHealthAccount}
 Write-Host '[10%] Preflight passed. Shared ssh-agent and gateway are preserved.'
 if($Mode -eq 'Apply'){
  Write-Host 'Create non-admin Windows account marketbrain-health and protected C:\ProgramData\MarketBrainPaytmHealth; test identity, storage access and empty per-account agent. No key import or task installation.'
  for($i=0;$i -lt 3;$i++){
   $password=Read-Host 'Choose a NEW Windows health-account password (14+ characters)' -AsSecureString
   $confirm=Read-Host 'Confirm that SAME new password' -AsSecureString
   $result=Get-PaytmAccountPasswordResult $password $confirm;$confirm.Dispose();$confirm=$null
   if($result -ceq 'CONFIRMED'){break}
   $password.Dispose();$password=$null;Write-Host "$result; no account created yet."
  }
  if($null -eq $password){throw 'HEALTH_ACCOUNT_PASSWORD_NOT_CONFIRMED'}
 }else{$password=Read-Host 'Existing marketbrain-health Windows account password' -AsSecureString}
 Invoke-PaytmHealthAccountSetup $report $password $run {
  Save-HealthAccount
  $pct=switch($report.stage){CREATE_DISABLED_ACCOUNT{20} PROTECTED_STORAGE{40} ENABLE_STANDARD_ACCOUNT{60} EXACT_ACCOUNT_PROBE{80} default{10}}
  Write-Progress -Activity 'Dedicated Windows health account' -Status $report.stage -PercentComplete $pct
  Write-Host "[$pct%] $($report.stage)"
 } -VerifyOnly:($Mode -eq 'Verify')
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(HEALTH_ACCOUNT|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_ACCOUNT_SETUP_FAILED'}
 $base=$_.Exception.GetBaseException();$report.failureDetails=@{type=$base.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber;nativeErrorCode=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null}}
}finally{
 if($null -ne $password){$password.Dispose()};if($null -ne $confirm){$confirm.Dispose()}
 Save-HealthAccount;Write-Progress -Activity 'Dedicated Windows health account' -Completed
 Write-Host "[100%] $($report.status)";Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Share the report before retrying. Do not delete the account or protected directory.'}
