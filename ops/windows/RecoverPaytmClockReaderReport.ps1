#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-reader-stage-f4990f6148224b49a80fc7bb481eb95f.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-reader-recovery-'+$run+'.json')
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;server=$null;sourceHashes=@{};elapsedSeconds=0;ordersEnabled=$false}
function Save-Report {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
try{
 Save-Report
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'AF4F25BED8C64EA45916DFC12B0E36EBE3E7B8B037BF494C66E442A7871DBBDE'){throw 'CLOCK_STAGE_EVIDENCE_MISMATCH'}
 $prior=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
 if($prior.runId -cne 'f4990f6148224b49a80fc7bb481eb95f' -or $prior.failure -cne 'CLOCK_STAGE_REPORT_NOT_CONFIRMED' -or $null -ne $prior.server){throw 'CLOCK_STAGE_PRIOR_REPORT_MISMATCH'}
 $run=$prior.runId;$report.sourceRunId=$run;$report.sourceHashes=$prior.sourceHashes
 Write-Host '[20%] Import existing VPS report only. NO VPS command, account creation or SSH change will run.'
 Write-Host 'Copy the original MB_CLOCK_STAGE_REPORT line from PuTTY (or the previous PowerShell input).'
 $answer=Read-Host 'Paste the complete MB_CLOCK_STAGE_REPORT line HERE, or press Enter to read it from the clipboard'
 $raw=if([string]::IsNullOrWhiteSpace($answer) -or $answer -ceq 'REPORT-COPIED'){Get-Clipboard -Raw}else{$answer}
 if($raw.Length -gt 16384){throw 'CLOCK_STAGE_REPORT_SIZE'}
 $text=($raw -replace '\s','')
 if($text -cnotmatch '^MB_CLOCK_STAGE_REPORT:([A-Za-z0-9+/]+={0,2})$'){throw 'CLOCK_STAGE_REPORT_FORMAT'}
 $v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))|ConvertFrom-Json
 if($v.version -ne 1 -or $v.runId -cne $run){throw 'CLOCK_STAGE_REPORT_IDENTITY'}
 $report.server=$v;Save-Report
 foreach($n in @('sshConfigurationChanged','sshAccessEnabled','ordersEnabled')){if($v.$n -isnot [bool] -or $v.$n){throw 'CLOCK_STAGE_UNEXPECTED_AUTHORITY'}}
 foreach($n in @('accountCreated','passwordLocked','programVerified','allowedCommandVerified','deniedCommandVerified','keylessVerified')){if($v.$n -isnot [bool] -or -not $v.$n){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}}
 if($v.failure -or $v.status -cne 'CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING'){throw 'CLOCK_STAGE_SERVER_REVIEW_REQUIRED'}
 $report.status='CLOCK_STAGE_REPORT_RECOVERED_INSTALLATION_REPORTED_PASSED'
}catch{$report.failure=if($_.Exception.Message -cmatch '^CLOCK_STAGE_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_STAGE_REPORT_REVIEW_REQUIRED'}}finally{
 Save-Report
 Write-Host "[100%] $($report.status)"
 Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Share the report. Do not rerun staging or remove the account manually.'}
