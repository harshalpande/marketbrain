#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-unattended-preflight-20261115-034000-c0e727fb8ab647ddb6bf02e39ba2197c.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-reader-stage-'+$run+'.json')
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;server=$null;sourceHashes=@{};elapsedSeconds=0;ordersEnabled=$false}
function Save-Report {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
try{
 Save-Report
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '943E5AB49FBD6FFE56C17EEFF005388E1C21C3F6BF0B5443E323FC0B68C6C502'){throw 'CLOCK_STAGE_EVIDENCE_MISMATCH'}
 $linux=Join-Path $PSScriptRoot '../linux'
 $reader=[IO.File]::ReadAllBytes((Join-Path $linux 'paytm_clock_reader.py'))
 $installer=[IO.File]::ReadAllBytes((Join-Path $linux 'stage_paytm_clock_reader.py'))
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($reader)).ToLowerInvariant()
 $report.sourceHashes.reader=$hash
 $report.sourceHashes.installer=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($installer))
 $report.sourceHashes.controller=(Get-FileHash -LiteralPath $PSCommandPath).Hash
 $reader64=[Convert]::ToBase64String($reader);$installer64=[Convert]::ToBase64String($installer)
 $command=@"
sudo -n /usr/bin/python3 -I - <<'MB_CLOCK_STAGE'
import base64
exec(compile(base64.b64decode('$installer64'), '<reviewed-clock-stage>', 'exec'))
r = stage('$reader64', '$hash', '$run')
print('MB_CLOCK_STAGE_REPORT:' + base64.b64encode(json.dumps(r, separators=(',', ':')).encode()).decode())
MB_CLOCK_STAGE
"@
 Set-Clipboard -Value $command
 Write-Host '[20%] VPS stage command copied. Open your verified marketbrain-admin PuTTY session.'
 Write-Host 'In PuTTY run sudo -v and enter your administrator password there. Then paste the clipboard command.'
 Write-Host 'This creates only a locked, keyless clock account/program. No SSH reload, key installation or gateway restart.'
 Write-Host 'After it finishes, copy the complete MB_CLOCK_STAGE_REPORT: line from PuTTY to the clipboard.'
 if((Read-Host 'Back HERE in PowerShell type REPORT-COPIED after copying the report') -cne 'REPORT-COPIED'){throw 'CLOCK_STAGE_REPORT_NOT_CONFIRMED'}
 $raw=Get-Clipboard -Raw
 if($raw.Length -gt 16384){throw 'CLOCK_STAGE_REPORT_SIZE'}
 $text=($raw -replace '\s','')
 if($text -cnotmatch '^MB_CLOCK_STAGE_REPORT:([A-Za-z0-9+/]+={0,2})$'){throw 'CLOCK_STAGE_REPORT_FORMAT'}
 $v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))|ConvertFrom-Json
 if($v.version -ne 1 -or $v.runId -cne $run){throw 'CLOCK_STAGE_REPORT_IDENTITY'}
 $report.server=$v;Save-Report
 foreach($n in @('sshConfigurationChanged','sshAccessEnabled','ordersEnabled')){if($v.$n -isnot [bool] -or $v.$n){throw 'CLOCK_STAGE_UNEXPECTED_AUTHORITY'}}
 foreach($n in @('accountCreated','passwordLocked','programVerified','allowedCommandVerified','deniedCommandVerified','keylessVerified')){if($v.$n -isnot [bool] -or -not $v.$n){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}}
 if($v.failure -or $v.status -cne 'CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING'){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}
 $report.status=$v.status
}catch{$report.failure=if($_.Exception.Message -cmatch '^CLOCK_STAGE_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_STAGE_REPORT_REVIEW_REQUIRED'}}finally{
 Save-Report
 Write-Host "[100%] $($report.status)"
 Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Share the report. Do not rerun staging or remove the account manually.'}
