#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedProxy.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedProxyRecovery.ps1')
$checks=0
function Check($Condition,$Name){if(-not $Condition){throw "RECOVERY_TEST_$Name"};$script:checks++}
function Reject($Body,$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
$original='25659b497afb4d088bf9fbf309f791b1';$run='a'*32
$bad="BEGIN_MANAGED_REPORT_$original`n{broken-json}`nEND_MANAGED_REPORT_$original"
$snapshot="ActiveState=active`nUnitFileState=enabled"
function Encode($Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
$report="BEGIN_MANAGED_RECOVERY_$run`nSTATUS=CAPTURED`nLOG_MATCH_COUNT=1`nORIGINAL_RUN=$original`nREPORT_BASE64=$(Encode $bad)`nSNAPSHOT_BASE64=$(Encode $snapshot)`nEND_MANAGED_RECOVERY_$run"
$r=Read-PaytmManagedRecoveryReport $report $original $run
Check ($r.originalReport -ceq $bad) 'MALFORMED_BYTES_PRESERVED'
Check ($r.currentServiceSnapshot -ceq $snapshot) 'STATE_CAPTURED'
try{Read-PaytmManagedProxyReport $bad $original;throw 'EXPECTED_ERROR'}catch{Check ($_.Exception.Message -ceq 'MANAGED_REPORT_INVALID_JSON') 'JSON_DIAGNOSTIC'}
$r=Read-PaytmManagedRecoveryReport ($report.Replace("`n","`r`n")) $original $run;Check ($r.logMatchCount -eq 1) 'CRLF'
Reject {Read-PaytmManagedRecoveryReport ($report+"`n"+$report) $original $run} 'DUPLICATE'
Reject {Read-PaytmManagedRecoveryReport $report ('b'*32) $run} 'WRONG_ORIGINAL'
Reject {Read-PaytmManagedRecoveryReport $report $original ('b'*32)} 'WRONG_RECOVERY'
Reject {Read-PaytmManagedRecoveryReport ('x'*65537) $original $run} 'OVERSIZE'
Reject {Read-PaytmManagedRecoveryReport ($report.Replace((Encode $bad),'A===')) $original $run} 'BAD_BASE64'
Reject {Read-PaytmManagedRecoveryReport ($report.Replace((Encode $bad),'/w==')) $original $run} 'BAD_UTF8'
$missing=$report.Replace('STATUS=CAPTURED','STATUS=LOG_MATCH_REVIEW').Replace('LOG_MATCH_COUNT=1','LOG_MATCH_COUNT=0').Replace((Encode $bad),'')
$r=Read-PaytmManagedRecoveryReport $missing $original $run;Check ($r.logMatchCount -eq 0 -and $r.originalReport -ceq '') 'MISSING_LOG_REPORTED'
$payload=Get-PaytmManagedRecoveryPayload $original $run
Check ($payload.StartsWith('sudo -n env SSH_CONNECTION=') -and $payload.EndsWith(" </dev/tty`n")) 'TTY_LAUNCHER'
Reject {Get-PaytmManagedRecoveryPayload 'x;reboot' $run} 'INJECTION'
$body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\ReadPaytmManagedProxyReport.sh')).Replace("`r`n","`n")
# Real Bash extraction on disposable files; no systemd, SSH, root or network calls.
$fixture=@'
set -euo pipefail
root=$(mktemp -d)
trap 'rm -f -- "$root/log"; rmdir -- "$root"' EXIT
original=25659b497afb4d088bf9fbf309f791b1
printf 'noise\nBEGIN_MANAGED_REPORT_%s\n{broken-json}\nEND_MANAGED_REPORT_%s\nnoise\n' "$original" "$original" >"$root/log"
actual=$(mr_extract "$root/log" "$original")
expected=$(printf 'BEGIN_MANAGED_REPORT_%s\n{broken-json}\nEND_MANAGED_REPORT_%s' "$original" "$original")
[ "$actual" = "$expected" ]
if mr_extract "$root/log" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null; then exit 1; fi
printf 'BEGIN_MANAGED_REPORT_%s\n{}\n' "$original" >"$root/log"
if mr_extract "$root/log" "$original" >/dev/null; then exit 1; fi
printf 'BEGIN_MANAGED_REPORT_%s\n{}\nEND_MANAGED_REPORT_%s\nBEGIN_MANAGED_REPORT_%s\n{}\nEND_MANAGED_REPORT_%s\n' "$original" "$original" "$original" "$original" >"$root/log"
if mr_extract "$root/log" "$original" >/dev/null; then exit 1; fi
printf 'FOUR_EXTRACTION_CASES_PASSED'
'@
foreach($source in @($payload,($body+"`n"+$fixture))){
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'
 $info.Arguments=if($source -ceq $payload){'--noprofile --norc -n'}else{'--noprofile --norc -s'}
 $info.UseShellExecute=$false;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
 $p=[Diagnostics.Process]::new();$p.StartInfo=$info
 try{$null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync();$p.StandardInput.Write($source);$p.StandardInput.Close();if(-not $p.WaitForExit(30000)){$p.Kill();throw 'BASH_TIMEOUT'};Check ($p.ExitCode -eq 0) ('NATIVE_BASH_'+$stderr.Result)}finally{$p.Dispose()}
}
[pscustomobject]@{status='MANAGED_REPORT_RECOVERY_PASSED';assertions=$checks;nativeExtractionCases=4;vpsContacted=$false}|ConvertTo-Json
