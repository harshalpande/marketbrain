#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-key-preparation-c192c546fbc2470f961341ea21f52266.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-key-authorization-'+$run+'.json')
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;server=$null;sourceHashes=@{};elapsedSeconds=0;ordersEnabled=$false}
function Save-Report {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
try{
 Save-Report
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '6DDEB3B0B3DAFC9F67E4D6FFF8DAD671D57860B3ECD944778E489FBE4400D2DE'){throw 'CLOCK_STAGE_EVIDENCE_MISMATCH'}
 $linux=Join-Path $PSScriptRoot '../linux'
 $prior=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
 $hash='04623f839d2c54095d836052a20c423867d91b309e3f89e179ca32664f5e519f'
 if($hash -cnotmatch '^[a-f0-9]{64}$'){throw 'CLOCK_POLICY_READER_HASH'}
 if($prior.fingerprint -cne 'SHA256:TqoeCxI+3t+k2XTi8E6f+7iX4HCyhc1gshoZqnfyaX0'){throw 'CLOCK_KEY_FINGERPRINT'}
 $base=[IO.File]::ReadAllBytes((Join-Path $linux 'stage_paytm_clock_reader.py'))
 $policy=[IO.File]::ReadAllBytes((Join-Path $linux 'install_paytm_clock_policy.py'))
 $auth=[IO.File]::ReadAllBytes((Join-Path $linux 'authorize_paytm_clock_key.py'))
 $report.sourceHashes.authorization=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($auth))
 $auth64=[Convert]::ToBase64String($auth)
 $report.sourceHashes.base=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($base))
 $report.sourceHashes.policy=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($policy))
 $report.sourceHashes.reader=$hash
 $report.sourceHashes.controller=(Get-FileHash -LiteralPath $PSCommandPath).Hash
 $base64=[Convert]::ToBase64String($base);$policy64=[Convert]::ToBase64String($policy)
 $command=@"
sudo -n env SSH_CONNECTION="`$SSH_CONNECTION" /usr/bin/python3 -I - <<'MB_CLOCK_KEY'
import base64
exec(compile(base64.b64decode('$base64'), '<reviewed-clock-helpers>', 'exec'))
exec(compile(base64.b64decode('$policy64'), '<reviewed-clock-policy>', 'exec'))
exec(compile(base64.b64decode('$auth64'), '<reviewed-clock-authorization>', 'exec'))
r = authorize_key('$hash', '$run')
print('MB_CLOCK_KEY_REPORT:' + base64.b64encode(json.dumps(r, separators=(',', ':')).encode()).decode())
MB_CLOCK_KEY
"@
 Set-Clipboard -Value $command
 Write-Host '[20%] VPS stage command copied. Open your verified marketbrain-admin PuTTY session.'
 Write-Host 'In PuTTY run sudo -v and enter your administrator password there. Then paste the clipboard command.'
 Write-Host 'This authorizes only the reviewed public clock key after policy checks. No private key transfer, SSH reload or gateway restart.'
 Write-Host 'After it finishes, copy the complete MB_CLOCK_KEY_REPORT: line from PuTTY to the clipboard.'
 $answer=Read-Host 'Paste the complete MB_CLOCK_KEY_REPORT line HERE, or press Enter to read it from the clipboard'
 $raw=if([string]::IsNullOrWhiteSpace($answer) -or $answer -ceq 'REPORT-COPIED'){Get-Clipboard -Raw}else{$answer}
 if($raw.Length -gt 16384){throw 'CLOCK_STAGE_REPORT_SIZE'}
 $text=($raw -replace '\s','')
 if($text -cnotmatch '^MB_CLOCK_KEY_REPORT:([A-Za-z0-9+/]+={0,2})$'){throw 'CLOCK_STAGE_REPORT_FORMAT'}
 $v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))|ConvertFrom-Json
 if($v.version -ne 1 -or $v.runId -cne $run){throw 'CLOCK_STAGE_REPORT_IDENTITY'}
 $report.server=$v;Save-Report
 foreach($n in @('sshReloaded','privateKeyTransferred','loginTested','ordersEnabled')){if($v.$n -isnot [bool] -or $v.$n){throw 'CLOCK_STAGE_UNEXPECTED_AUTHORITY'}}
 foreach($n in @('keyInstalled','passwordLocked','effectivePolicyVerified','readerVerified','publicKeyReadable')){if($v.$n -isnot [bool] -or -not $v.$n){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}}
 if($v.failure -or $v.rollbackFailure -or $v.status -cne 'CLOCK_PUBLIC_KEY_AUTHORIZED_LOGIN_AND_CUSTODY_PENDING'){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}
 $report.status=$v.status
}catch{$report.failure=if($_.Exception.Message -cmatch '^CLOCK_(STAGE|POLICY|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_STAGE_REPORT_REVIEW_REQUIRED'}}finally{
 Save-Report
 Write-Host "[100%] $($report.status)"
 Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Share the report. Do not rerun authorization or edit authorized_keys manually.'}
