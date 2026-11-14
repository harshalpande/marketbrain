#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-policy-5bcacd66db8749e19d8513323978439d.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmClockKeyPreparation.ps1')
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;encrypted=$false;privateKeyPath=$null;publicKey=$null;fingerprint=$null;directoryAclVerified=$false;vpsChanged=$false;taskInstalled=$false;ordersEnabled=$false;elapsedSeconds=0;sourceHashes=@{}}
$null=New-Item -ItemType Directory $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-key-preparation-'+$run+'.json')
function Save-Report {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
try{
 Save-Report
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'ACFAE34FA921547D547BAAE3FEF1F156CA0AB85FBC71534D32D982E5AAD489BF'){throw 'CLOCK_KEY_EVIDENCE_MISMATCH'}
 foreach($n in @('NewPaytmClockReaderKey.ps1','PaytmClockKeyPreparation.ps1','PaytmGatewayKeyCustody.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 $base=[Environment]::GetFolderPath('LocalApplicationData')
 if(-not [IO.Path]::IsPathFullyQualified($base) -or $base.StartsWith('\\')){throw 'CLOCK_KEY_LOCAL_PROFILE_REQUIRED'}
 $directory=Join-Path $base ('MarketBrainClockKeys-'+$run)
 if(Test-Path -LiteralPath $directory){throw 'CLOCK_KEY_DIRECTORY_EXISTS'}
 $null=[IO.Directory]::CreateDirectory($directory)
 Set-PaytmClockKeyDirectory $directory;$report.directoryAclVerified=$true
 $key=Join-Path $directory 'marketbrain-clock-reader.openssh';$report.privateKeyPath=$key;Save-Report
 Write-Host '[25%] Generate a dedicated clock-reader key in a restricted local directory.'
 New-PaytmClockKeyMaterial $key
 Write-Host '[75%] Verify encrypted OpenSSH structure and matching Ed25519 public identity.'
 $pub=Read-PaytmClockPublicKey ($key+'.pub')
 $v=Test-PaytmEncryptedKeyFile $key $pub.blob
 if(-not $v.encrypted -or $v.rounds -lt 64 -or $v.fingerprint -cne $pub.fingerprint){throw 'CLOCK_KEY_ENCRYPTION_OR_IDENTITY'}
 $report.encrypted=$true;$report.publicKey=$pub.line;$report.fingerprint=$pub.fingerprint
 $report.status='CLOCK_ENCRYPTED_KEY_PREPARED_CUSTODY_AND_AUTHORIZATION_PENDING'
}catch{$report.failure=if($_.Exception.Message -cmatch '^(CLOCK_KEY|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_KEY_PREPARATION_FAILED'}}finally{
 Save-Report;Write-Host "[100%] $($report.status)";Write-Host "Share this ONE JSON file: $path"
 Write-Host 'Keep the private key and passphrase locally. Never upload the private-key file. No VPS key or task was installed.'
}
if($report.failure){throw 'Share the JSON before retrying. Generated files remain in the restricted directory; encryption was not accepted.'}
