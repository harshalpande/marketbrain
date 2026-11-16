# Definitions only. Interactive private-key decryption stays in native OpenSSH.
function Invoke-ClockLoginNative([string]$Executable,[string[]]$Arguments,[int]$Seconds=180) {
 $info=[Diagnostics.ProcessStartInfo]::new($Executable)
 $info.UseShellExecute=$false
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 foreach($a in $Arguments){$info.ArgumentList.Add($a)}
 foreach($n in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','DISPLAY')){$null=$info.Environment.Remove($n)}
 $info.Environment['SSH_ASKPASS_REQUIRE']='never'
 $p=[Diagnostics.Process]::new();$p.StartInfo=$info;$started=$false
 try{
  $started=$p.Start();if(-not $started){throw 'CLOCK_LOGIN_START_FAILED'}
  $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($Seconds*1000)){throw 'CLOCK_LOGIN_TIMEOUT'}
  [pscustomobject]@{exitCode=$p.ExitCode;stdout=$out.GetAwaiter().GetResult();stderr=$err.GetAwaiter().GetResult()}
 }finally{if($started -and -not $p.HasExited){$p.Kill($true);$null=$p.WaitForExit(5000)};$p.Dispose()}
}
function Assert-ClockLoginReply($Result,[string]$Nonce,[bool]$Allowed){
 if($Allowed){
  if($Result.exitCode -ne 0 -or $Result.stdout.Trim() -cnotmatch ('^MB_CLOCK_V1\|'+[regex]::Escape($Nonce)+'\|([0-9]{13})\|(yes|no)$')){throw 'CLOCK_LOGIN_RESPONSE_INVALID'}
  return [pscustomobject]@{epochMilliseconds=[long]$Matches[1];ntpSynchronized=($Matches[2] -ceq 'yes')}
 }
 if($Result.exitCode -ne 1 -or $Result.stdout.Trim() -or $Result.stderr -cnotmatch '(?m)^CLOCK_READ_DENIED_OR_UNAVAILABLE\r?$'){throw 'CLOCK_LOGIN_DENIAL_NOT_PROVEN'}
 return $null
}
