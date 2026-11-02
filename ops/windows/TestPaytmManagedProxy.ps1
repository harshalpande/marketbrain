#Requires -Version 7.0
[CmdletBinding()]param([switch]$AsObject,[string]$BashPath=(Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedProxy.ps1')
$checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "MANAGED_TEST_$Name"};$script:checks++}
function Reject([scriptblock]$Body,[string]$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
$id='a'*32
$value=[ordered]@{version=1;runId=$id;success=$true;stage='COMPLETE';exitCode=0;failureLine=0;elapsedSeconds=45;
 baselineVerified=$true;backupVerified=$true;effectivePolicyVerified=$true;crashRestartVerified=$true;disableVerified=$true;
 conditionBlocksStart=$true;tlsVerified=$true;httpStatus=503;denialsVerified=$true;bootEnabled=$true;finalRunning=$true;cleanupPassed=$true;credentialsUsed=$false;ordersEnabled=$false}
function Wrap($Object){"BEGIN_MANAGED_REPORT_$id`n"+($Object|ConvertTo-Json -Compress)+"`nEND_MANAGED_REPORT_$id"}
$text=Wrap $value;$parsed=Read-PaytmManagedProxyReport $text $id
Assert-PaytmManagedProxyPassed $parsed;Check ($parsed.httpStatus -eq 503) 'TLS_503_NOT_BROKER_READINESS'
$parsed=Read-PaytmManagedProxyReport ($text.Replace("`n","`r`n")) $id;Assert-PaytmManagedProxyPassed $parsed;Check $true 'CRLF_REPORT'
Reject {Read-PaytmManagedProxyReport ($text+"`n"+$text) $id} 'DUPLICATE'
Reject {Read-PaytmManagedProxyReport $text ('b'*32)} 'WRONG_RUN'
Reject {Read-PaytmManagedProxyReport ('x'*65537) $id} 'SIZE'
foreach($field in @('success','baselineVerified','backupVerified','effectivePolicyVerified','crashRestartVerified','disableVerified','conditionBlocksStart','tlsVerified','denialsVerified','bootEnabled','finalRunning','cleanupPassed')){
    $copy=$parsed.PSObject.Copy();$copy.$field=$false;Reject {Assert-PaytmManagedProxyPassed $copy} 'MISSING_PROOF'
    $copy.$field='true';Reject {Read-PaytmManagedProxyReport (Wrap $copy) $id} 'BOOLEAN_TYPE'
}
foreach($field in @('credentialsUsed','ordersEnabled')){$copy=$parsed.PSObject.Copy();$copy.$field=$true;Reject {Read-PaytmManagedProxyReport (Wrap $copy) $id} 'SCOPE'}
$copy=$parsed.PSObject.Copy();$copy.exitCode=1;Reject {Assert-PaytmManagedProxyPassed $copy} 'EXIT_CODE'
$copy=$parsed.PSObject.Copy();$copy.httpStatus=0;Reject {Assert-PaytmManagedProxyPassed $copy} 'NO_TLS_STATUS'
$copy=$parsed.PSObject.Copy();$copy.stage='VERIFY_TLS_AND_DENIALS';Reject {Assert-PaytmManagedProxyPassed $copy} 'INCOMPLETE'
foreach($field in @('version','exitCode','failureLine','elapsedSeconds','httpStatus')){$copy=$parsed.PSObject.Copy();$copy.$field='0';Reject {Read-PaytmManagedProxyReport (Wrap $copy) $id} 'NUMBER_TYPE'}
$payload=Get-PaytmManagedProxyPayload $id
Check ($payload.Contains("gm_main '$id'") -or $payload.Contains('gm_main')) 'MANAGED_ENTRY'
Check ($payload.StartsWith('sudo -n env SSH_CONNECTION=') -and $payload.EndsWith(" </dev/tty`n")) 'VERIFIED_LAUNCHER'
Check (-not $payload.Contains('then tg_main') -and -not $payload.Contains('then pg_main')) 'OLD_INSTALLERS_NOT_INVOKED'
Reject {Get-PaytmManagedProxyPayload 'x;reboot'} 'RUN_INJECTION'
foreach($source in @($payload)+@('InstallPaytmTunnelIdentity.sh','StagePaytmLoopbackProxy.sh','ManagePaytmProxyLifecycle.sh'|ForEach-Object{[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$_"))})){
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$BashPath;$info.Arguments='--noprofile --norc -n'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try{
        $null=$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($source.Replace("`r`n","`n"));$process.StandardInput.Close()
        if(-not $process.WaitForExit(15000)){$process.Kill();throw 'BASH_SYNTAX_TIMEOUT'}
        Check ($process.ExitCode -eq 0) ('BASH_SYNTAX_'+$stderr.Result)
    }finally{$process.Dispose()}
}
$result=[pscustomobject]@{status='MANAGED_PROXY_COLLECTOR_PASSED';assertions=$checks;remoteExecutionTested=$false;networkContacted=$false}
if($AsObject){$result}else{$result|ConvertTo-Json}
