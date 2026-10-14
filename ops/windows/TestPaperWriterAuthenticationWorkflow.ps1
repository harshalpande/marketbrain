#Requires -Version 7.0
# Offline: synthetic fixtures and mocked native/database calls. No real credential or runtime access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterAuthentication.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterHbaPlan.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$script:checks=0
function Check($Value,[string]$Why){if(-not $Value){throw $Why};$script:checks++}
function Reject([scriptblock]$Action){$rejected=$false;try{$null=& $Action}catch{$rejected=$true};Check $rejected 'Expected rejection'}
# Reuse only the existing synthetic plan factory, never execute the credential runner suite here.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaperWriterCredentialWorkflow.ps1'),[ref]$null,[ref]$null)
$sample=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Sample'},$false)
. ([scriptblock]::Create($sample.Extent.Text))
$golden=New-PaperCredentialVerifier ([byte[]](0..47));$id='b'*32
function DbReceipt([string]$Phase){[pscustomobject]@{version='PAPER_WRITER_AUTH_DB_V1';phase=$Phase;runId=$id;writerLoginEnabled=($Phase -ceq 'Lease');helperLoginEnabled=$false;writerSessions=0;leaseSecondsRemaining=119.2;serverStartEpoch='123.000000';accountRowsWritten=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}}
function ProbeReceipt([string]$Phase){[pscustomobject]@{version='PAPER_WRITER_AUTH_PROBE_V1';phase=$Phase;runId=$script:runId;status='PASSED';connectorSha256=('a'*64);driverSha256=('b'*64);accountRowsWritten=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}}
$watch=[Diagnostics.Stopwatch]::StartNew()
foreach($phase in @('Lease','Revoke','Drain','Readback')){
 $sql=New-PaperAuthenticationSql $phase (Sample).plan $golden $id
 Check ($sql -notmatch '__[A-Z_]+__') 'SQL resolved'
 Check ($sql.Contains("statement_timeout='15s'") -and $sql.Contains("lock_timeout='3s'")) 'timeouts'
 Check ($sql.Contains('Authentication target mismatch') -and $sql.Contains('Authentication credential changed')) 'target and credential guard'
 Check ($sql -notmatch '(?i)\bGRANT\s|\bREVOKE\s|\bINSERT\s|\bUPDATE\s+public\.|\bDELETE\s+FROM') 'no grant or row mutations'
 Check ($sql.IndexOf('COMMIT;') -lt $sql.LastIndexOf('SELECT jsonb_build_object')) 'receipt after commit'
 Check ($sql.Contains('LOGIN VALID UNTIL %L') -eq ($phase -ceq 'Lease')) 'only lease enables'
 Check ($sql.Contains('Column mutation boundary mismatch') -eq ($phase -ceq 'Lease')) 'revoke not blocked by grant drift'
 Check ($sql.Contains('pg_terminate_backend') -eq ($phase -ceq 'Drain')) 'only explicit drain'
 if($phase -ceq 'Lease'){Check ($sql.Contains("interval '120 seconds'") -and $sql.Contains('Authentication HBA drift')) 'lease bound and HBA guard'}
 if($phase -ceq 'Revoke'){Check ($sql.Contains("NOLOGIN VALID UNTIL 'infinity'")) 'revoke durable'}
 Assert-PaperAuthenticationReceipt (DbReceipt $phase) $phase $id;$script:checks++
}
Reject {New-PaperAuthenticationSql Lease (Sample).plan $golden "x';--"}
Reject {New-PaperAuthenticationSql Lease (Sample).plan 'bad' $id}
foreach($flag in @('helperLoginEnabled','accountRowsWritten','applicationWriterActivated','actionExecutionEnabled')){
 $r=DbReceipt 'Revoke';$r.$flag=$true;Reject {Assert-PaperAuthenticationReceipt $r 'Revoke' $id}
 $r.$flag='false';Reject {Assert-PaperAuthenticationReceipt $r 'Revoke' $id}
}
foreach($value in @(0,60,121,'119',$true)){$r=DbReceipt 'Lease';$r.leaseSecondsRemaining=$value;Reject {Assert-PaperAuthenticationReceipt $r 'Lease' $id}}
$r=DbReceipt 'Readback';$r.writerSessions=1;Reject {Assert-PaperAuthenticationReceipt $r 'Readback' $id}
$r=DbReceipt 'Revoke';$r.writerLoginEnabled=$true;Reject {Assert-PaperAuthenticationReceipt $r 'Revoke' $id}
foreach($fail in @('NONE','Checkpoint','Lease','Probe','Revoke','Drain','Readback')){
 $script:trace=[Collections.Generic.List[string]]::new();$script:fail=$fail
 function Run([string]$Step){$script:trace.Add($Step);if($Step -ceq $script:fail){throw 'SYNTHETIC_FAILURE'}}
 try{Invoke-PaperAuthenticationWindow -Checkpoint {Run Checkpoint} -Lease {Run Lease} -Probe {Run Probe} -Revoke {Run Revoke} -Drain {Run Drain} -Readback {Run Readback}}catch{}
 if($fail -ceq 'Checkpoint'){Check (($script:trace -join ',') -ceq 'Checkpoint') 'no lease without checkpoint'}
 elseif($fail -cin @('Lease','Probe')){Check (($script:trace -join ',').EndsWith('Revoke,Drain,Readback')) 'unknown commit and probe failure revoke'}
 elseif($fail -ceq 'Revoke'){Check (($script:trace -join ',').EndsWith('Revoke')) 'no false readback after failed revoke'}
 else{Check ($script:trace.Contains('Revoke')) 'revoke always called'}
}
# Actual orchestration script; replace only external interfaces and local fixture paths.
# First exercise the REAL stdin/deadline helper against a harmless local PowerShell child, not Docker.
$child=(Microsoft.PowerShell.Management\Get-Process -Id $PID).Path
$inputBytes=[Text.Encoding]::ASCII.GetBytes('a'*64)
$native=Invoke-PaperAuthenticationProcess $child @('-NoProfile','-Command','$b=[Console]::OpenStandardInput().ReadByte();$n=0;while($b -ne -1){$n++;$b=[Console]::OpenStandardInput().ReadByte()};[Console]::Write($n)') $PSScriptRoot $inputBytes 15
Check ($native.exitCode -eq 0 -and $native.stdout -ceq '64') 'real child receives exact 64-byte stdin and EOF'
Reject {Invoke-PaperAuthenticationProcess $child @('-NoProfile','-Command','[Threading.Thread]::Sleep(15000)') $PSScriptRoot $inputBytes 1}
Reject {Invoke-PaperAuthenticationProcess 'C:\nonexistent-auth-probe.exe' @() $PSScriptRoot $inputBytes 1}
[Array]::Clear($inputBytes,0,$inputBytes.Length)
$root=Join-Path ([IO.Path]::GetTempPath()) ('writer-auth-offline-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source=Get-Content (Join-Path $PSScriptRoot 'TestPaperWriterAuthentication.ps1') -Raw
$mocked=[regex]::Replace($source,'(?m)^\. \(Join-Path \$PSScriptRoot .*\)\r?$','')
$mocked=$mocked.Replace("[IO.Path]::GetFullPath((Join-Path `$PSScriptRoot '../..'))",("'"+$repo.Replace("'","''")+"'"))
$mocked=$mocked.Replace("'C:\MarketBrainData\Secrets\PaperReviewWriter\writer.dpapi'",'$script:credentialFixture')
$runner=[scriptblock]::Create($mocked)
$installed=Join-Path $root 'installed.json';$acceptedCredential=Join-Path $root 'credential.json'
Save-NumericalHistoryReport ((Sample)|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable) $installed -Compact
Save-NumericalHistoryReport @{status='WRITER_CREDENTIAL_STAGED_LOGIN_DISABLED'} $acceptedCredential -Compact
function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40};if($script:case -ceq 'dirty' -and $args -contains 'status'){' M user-file'}}
function Get-FileHash {param($LiteralPath,$Algorithm='SHA256')
 if($LiteralPath -ceq $installed){return [pscustomobject]@{Hash='E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'}}
 if($LiteralPath -ceq $acceptedCredential){return [pscustomobject]@{Hash=$(if($script:case -ceq 'bad-evidence'){'0'*64}else{'392C6ADB2BC0CD792ED86EBA3E0321E248F687F27FF439C1DD95DA607D99FE16'})}}
 Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source='SYNTHETIC.exe'}}
function Read-PaperCredential {param($Path,$Entropy);if($script:case -ceq 'custody-fail'){throw 'CUSTODY_SYNTHETIC_FAILURE'};return ,[byte[]](0..47)}
function Read-Host {param($Prompt,[switch]$AsSecureString)
 if($AsSecureString){return ConvertTo-SecureString 'SYNTHETIC_ADMIN_SECRET' -AsPlainText -Force}
 if($Prompt -ceq 'Confirm database name'){return 'marketbrain'}
 if($Prompt -like 'Keep other*'){if($script:case -ceq 'cancel'){return 'NO'};return 'TEST_TEMPORARY_LOGIN'}
 if($Prompt -like 'Type RESTORE*'){return 'RESTORE_NOLOGIN'};if($Prompt -like '*username*'){return 'postgres'};throw 'Unexpected prompt'
}
function Invoke-PaperInstallerPsql($Exe,$Database,$Port,$Admin,$Password,$Sql){
 Check ($Password -ceq 'SYNTHETIC_ADMIN_SECRET' -and -not $Sql.Contains($Password)) 'admin not in SQL'
 $operation=[regex]::Match($Sql,"'phase','(Lease|Revoke|Drain|Readback|Verify)'").Groups[1].Value
 $script:dbCalls.Add($operation);$exit=0
 if($operation -ceq 'Verify'){$value=@{version='PAPER_WRITER_CREDENTIAL_CHECK_V1';phase='Verify';planHash=('a'*32);state='MATCH';writerLoginEnabled=$false;helperLoginEnabled=$false;accountRowsWritten=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}}
 else{$value=DbReceipt $operation;$value.runId=[regex]::Match($Sql,"'runId','([a-f0-9]{32})'").Groups[1].Value}
 if($operation -ceq 'Lease'){
  $script:leaseSeen=$true
  $checkpoint=Get-ChildItem -LiteralPath $script:out -Filter 'paper-writer-authentication-*.json'|Select-Object -First 1|Get-Content -Raw|ConvertFrom-Json
  Check $checkpoint.leaseAttempted 'durable marker before SQL'
  if($script:case -ceq 'lease-lost-receipt'){$exit=3}
 }
 if($operation -ceq 'Revoke' -and $script:case -ceq 'revoke-fail'){$exit=3}
 if($operation -ceq 'Drain' -and $script:case -ceq 'drain-fail'){$exit=3}
 if($operation -ceq 'Readback' -and $script:leaseSeen -and $script:case -ceq 'sessions-remain'){$value.writerSessions=1}
 if($operation -ceq 'Verify' -and $script:case -ceq 'grant-drift'){$exit=3}
 return @{exitCode=$exit;timedOut=$false;stdout=($value|ConvertTo-Json -Compress);stderrCharacters=0;elapsedSeconds=0.01;sqlStates=@();assertionFailures=@()}
}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
 $text='';$exit=0
 if($Arguments[0] -ceq 'ps'){$text=if($script:case -ceq 'ambiguous-container'){"abc123abc123`nabc123abc124"}else{'abc123abc123'}}
 if($Arguments -contains 'in.marketbrain.paper.PaperApplicationRouteProbe'){
  $text=@{version='PAPER_APPLICATION_ROUTE_V1';status='READ_ONLY_APPLICATION_ROUTE_OBSERVED';database='marketbrain';databaseOid='123';serverPort=5432;serverStartEpoch='123.000000';applicationName=('mb-route-'+$Arguments[-1]);applicationUser='marketbrain_app';sessionUser='marketbrain_app';clientAddress='127.0.0.1';serverAddress='127.0.0.1';readOnly=$true;databaseWritesPerformed=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false}|ConvertTo-Json -Compress
  if($script:case -ceq 'app-route-fail'){$exit=2}
 }
 if($script:case -ceq 'cleanup-fail' -and $Arguments -contains 'rm'){$exit=1}
 return @{exitCode=$exit;timedOut=$false;stdout=$text;elapsedSeconds=0.01}
}
function Invoke-PaperAuthenticationProcess($Exe,$Arguments,$WorkingDirectory,$InputBytes,$LimitSeconds){
 Check ($InputBytes.Length -eq 64 -and $Arguments -notcontains ([Text.Encoding]::ASCII.GetString($InputBytes))) 'secret via stdin only'
 $operation=$Arguments[8];$script:runId=$Arguments[12]
 $value=ProbeReceipt $operation;$exit=0
 if($operation -ceq 'Active' -and $script:case -ceq 'active-fail'){$exit=2;$value=[pscustomobject]@{failureCode='AUTH_CONNECTION_OR_QUERY_FAILED'}}
 if($operation -ceq 'Disabled' -and $script:case -ceq 'disabled-fail'){$exit=2}
 if($operation -ceq 'Active' -and $script:case -ceq 'artifact-drift'){$value.connectorSha256='c'*64}
 return @{exitCode=$exit;stdout=($value|ConvertTo-Json -Compress);stderrCharacters=0;elapsedSeconds=0.01}
}
$cases=@('success','bad-evidence','dirty','custody-fail','cancel','ambiguous-container','grant-drift','disabled-fail','lease-lost-receipt','active-fail','artifact-drift','revoke-fail','drain-fail','sessions-remain','app-route-fail','cleanup-fail','recover')
try {
 foreach($script:case in $cases){
  $script:out=Join-Path $root $script:case;[void][IO.Directory]::CreateDirectory($script:out)
  $secretDir=Join-Path $script:out 'private';[void][IO.Directory]::CreateDirectory($secretDir);Protect-PaperHbaBackupAcl $secretDir -Directory
  $script:credentialFixture=Join-Path $secretDir 'writer.dpapi';$handle=[IO.File]::Open((Join-Path $secretDir 'credential.lock'),'CreateNew','Write');$handle.Dispose()
  $script:dbCalls=[Collections.Generic.List[string]]::new();$script:leaseSeen=$false
  $params=@{InstallationReportPath=$installed;CredentialReportPath=$acceptedCredential;OutputDirectory=$script:out;PostgreSqlBin=$script:out}
  [IO.File]::WriteAllBytes((Join-Path $script:out 'psql.exe'),[byte[]]@())
  if($script:case -ceq 'recover'){
   $prior=Join-Path $script:out 'prior.json';Save-NumericalHistoryReport @{version='PAPER_WRITER_AUTHENTICATION_V1';leaseRunId=('c'*32);leaseAttempted=$true;installationReportSha256='E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D';credentialReportSha256='392C6ADB2BC0CD792ED86EBA3E0321E248F687F27FF439C1DD95DA607D99FE16'} $prior -Compact
   $params.Mode='Recover';$params.RecoveryReportPath=$prior
  }
  try{& $runner @params|Out-Null}catch{}
  $file=Get-ChildItem -LiteralPath $script:out -Filter 'paper-writer-authentication-*.json'|Select-Object -First 1
  Check ($null -ne $file) ('report exists '+$script:case)
  $raw=Get-Content -LiteralPath $file.FullName -Raw;$v=$raw|ConvertFrom-Json
  Check ($raw -notmatch 'SYNTHETIC_ADMIN_SECRET|SCRAM-SHA-256|000102030405060708090a0b0c0d0e0f') 'no secret in report'
  Check (-not $v.accountRowsWritten -and -not $v.actionExecutionEnabled -and -not $v.applicationWriterActivated) 'scope flags'
  if($script:case -ceq 'success'){Check ($v.status -ceq 'WRITER_AUTHENTICATION_PASSED_LOGIN_DISABLED') ('success failed '+$v.failureCode);Check ($v.probes.Count -eq 3 -and $v.revocationVerified -and $v.cleanupComplete) 'all success gates'}
  elseif($script:case -ceq 'recover'){Check ($v.status -ceq 'WRITER_NOLOGIN_RECOVERED_RETEST_PENDING' -and -not $script:dbCalls.Contains('Lease')) 'recover never opens login'}
  else{Check ($v.status -cnotin @('WRITER_AUTHENTICATION_PASSED_LOGIN_DISABLED','WRITER_NOLOGIN_RECOVERED_RETEST_PENDING')) ('must fail '+$script:case)}
  if($script:leaseSeen){Check ($script:dbCalls.Contains('Revoke')) ('revoke attempted '+$script:case)}
  if($script:case -cin @('revoke-fail','drain-fail','sessions-remain')){Check ($v.status -ceq 'RECOVERY_REQUIRED_DO_NOT_RETEST' -and -not $v.revocationVerified) 'recovery explicit'}
 }
} finally {
 $resolved=[IO.Path]::GetFullPath($root)
 if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'writer-auth-offline-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
$watch.Stop();[pscustomobject]@{status='PASSED';assertions=$script:checks;runnerScenarios=$cases.Count;elapsedSeconds=$watch.Elapsed.TotalSeconds;databaseContacted=$false;dockerInvoked=$false}
