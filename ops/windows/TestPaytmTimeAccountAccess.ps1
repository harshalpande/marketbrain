#Requires -Version 7.0
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeAccountProbe.ps1')
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
Assert-TimeObservationAcl $root
$account=Get-LocalUser -Name 'marketbrain-health'
if($account.SID.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or -not $account.Enabled){throw 'TIME_ACCOUNT_IDENTITY'}
$null=Read-TimeObservation
$contract=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1'))
$password=$null
Write-Host '[10%] Verify local health-account snapshot access. No broker login, health publication or orders.'
Write-Host 'Enter the existing WINDOWS marketbrain-health password here only. It is not sent to the automation queue.'
try{
 $password=Read-Host 'marketbrain-health password' -AsSecureString
 Write-Progress -Activity 'Health account time access' -Status 'Running bounded background probe' -PercentComplete 30
 Write-Host '[30%] Checking the credential once with Windows; only on acceptance, register the limited task.'
 $r=Invoke-TimeAccountProbe $contract $password
}finally{if($password){$password.Dispose()};Write-Progress -Activity 'Health account time access' -Completed}
$r.sourceHashes=@{}
foreach($name in @('PaytmTimeObservation.ps1','PaytmTimeAccountProbe.ps1','TestPaytmTimeAccountAccess.ps1')){$r.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
$r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
$path=Join-Path $root 'account-probe-result.json';$temp=Join-Path $root ('result-'+[guid]::NewGuid().ToString('N')+'.new')
if(Test-Path -LiteralPath $path){Assert-TimeObservationAcl $path}
[IO.File]::WriteAllText($temp,($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $temp
if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
if($r.credentialCheck){Write-Host ('Windows credential accepted: '+$r.credentialCheck.accepted+'; code: '+$r.credentialCheck.win32Code)}
if(-not $r.passed){Write-Host '[100%] Report saved for automatic collection.';if($r.nativeFailure){Write-Host ('Windows codes: '+(@($r.nativeFailure.win32Codes) -join ', '));Write-Host ('Findings: '+(@($r.nativeFailure.findings) -join ', '));Write-Host 'Password correctness is not established by a generic failure.'};throw "TIME_ACCOUNT_REVIEW_REQUIRED: $($r.failure)"}
Write-Host '[100%] TIME_ACCOUNT_READ_VERIFIED. Report ready for automatic collection; no file upload needed.'
