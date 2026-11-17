#Requires -Version 5.1
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmHealthTokenCustody.ps1"
$count=0
function Check([bool]$Value){if(-not $Value){throw 'FIXTURE_FAILED'};$script:count++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed}
$token='fixture_only_012345678901234567890123456789'
$cipher=Protect-HealthToken $token
Check ((Unprotect-HealthToken $cipher) -ceq $token)
$cipher[$cipher.Length-1]=$cipher[$cipher.Length-1] -bxor 1
Reject {Unprotect-HealthToken $cipher}
Reject {Protect-HealthToken 'short'}
Reject {Protect-HealthToken ('x'*129)}
Reject {New-HealthTokenWorkerSource 'invalid' 'Verify'}
Reject {Protect-HealthToken "invalid'input"}
$script:mutation='';$script:bodies=@()
function Invoke-HealthTokenHttp($Token,$Command,$Body){
 if($Command -eq 'challenge'){
  $v=@{healthContractVersion='SERVER_TRANSPORT_V2';status='CHALLENGE';challenge='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';bootId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';validForSeconds=10;accepted=$false;ordersEnabled=$false}
  switch($script:mutation){'nonce'{$v.challenge='wrong'};'window'{$v.validForSeconds=20};'orders'{$v.ordersEnabled=$true};'string'{$v.accepted='false'}}
 }else{
  $script:bodies+=,$Body
  $v=@{healthContractVersion='SERVER_TRANSPORT_V2';status='UNHEALTHY_AND_LOCKED';bootId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';accepted=$false;ordersEnabled=$false}
  switch($script:mutation){'boot'{$v.bootId='cccccccc-cccc-cccc-cccc-cccccccccccc'};'accepted'{$v.accepted=$true};'status'{$v.status='HEALTHY'}}
 }
 [pscustomobject]$v
}
Check ((Test-HealthTokenAuthority $token) -ceq 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
foreach($m in @('nonce','window','orders','string','boot','accepted','status')){$script:mutation=$m;Reject {Test-HealthTokenAuthority $token}}
foreach($body in $script:bodies){Check ($body.Count -eq 6 -and $body.synchronizedClock -ceq $false -and $body.transportHealthy -ceq $false -and $body.lowerOffsetSeconds -eq 0 -and $body.upperOffsetSeconds -eq 0)}
foreach($mode in @('Stage','Verify')){
 $s=New-HealthTokenWorkerSource ('a'*32) $mode
 $errors=$null;$tokens=$null;$null=[Management.Automation.Language.Parser]::ParseInput($s,[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0)
 Check ($s.Contains("-1011'") -and -not $s.Contains('marketbrain-gateway') -and -not $s.Contains('PAPER_READ_TOKEN'))
 if($mode -eq 'Verify'){Check (-not $s.Contains($token))}
}
foreach($name in @('InstallPaytmHealthTokenCustody.ps1','PaytmHealthTokenCustody.ps1')){
 $errors=$null;$tokens=$null;$null=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot/$name",[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0)
}
# Execute generated worker with fixture identity and storage, real DPAPI, stubbed HTTP.
# This does not establish spare-account isolation; the runtime batch checks that.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('health-token-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$library=Join-Path $fixture 'library.ps1';Copy-Item -LiteralPath "$PSScriptRoot/PaytmHealthTokenCustody.ps1" -Destination $library
$stage=Join-Path $fixture ('token-'+('a'*32)+'.dpapi');$target=Join-Path $fixture 'health-token.dpapi'
function FixtureWorker([string]$Mode,[string]$InputToken,[bool]$DenyIdentity=$false){
 $s=New-HealthTokenWorkerSource ('a'*32) $Mode
 $s=$s.Replace('C:\ProgramData\MarketBrainPaytmHealth\token-custody',$fixture).Replace('C:\ProgramData\MarketBrainPaytmHealth\work',$fixture)
 $s=$s.Replace("'S-1-5-21-3041730714-102984520-3202743044-1011'",("'"+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+"'"))
 $s=$s.Replace('([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)','$false')
 if($DenyIdentity){$s=$s.Replace('$id.User.Value -cne','$id.User.Value -ceq')}
 $stub="function Test-HealthTokenAuthority([string]`$Token){if(`$Token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'HEALTH_TOKEN_FORMAT'};'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'}`r`n"
 $s=$s.Replace('$result=[ordered]',$stub+'$result=[ordered]')
 $i=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('& ([scriptblock]::Create([Console]::In.ReadToEnd()))'))))
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $i.EnvironmentVariables['MARKETBRAIN_HEALTH_CUSTODY_TRANSFER']=$InputToken
 $p=[Diagnostics.Process]::new();$p.StartInfo=$i
 try{
  $null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.StandardInput.WriteLine($s);$p.StandardInput.Close()
  if(-not $p.WaitForExit(15000)){ $p.Kill();throw 'FIXTURE_TIMEOUT'}
  Check ($p.ExitCode -eq 0 -and -not $o.Result.Contains($token) -and -not $e.Result.Contains($token))
  $o.Result|ConvertFrom-Json
 }finally{$p.Dispose()}
}
try{
 $v=FixtureWorker 'Stage' $token;Check ($v.authenticated -and $v.encrypted -and -not $v.failure)
 Copy-Item -LiteralPath $stage -Destination $target
 $v=FixtureWorker 'Verify' '';Check ($v.authenticated -and $v.locked -and -not $v.failure)
 $v=FixtureWorker 'Stage' 'short';Check ($v.failure -ceq 'HEALTH_TOKEN_FORMAT')
 $v=FixtureWorker 'Verify' '' $true;Check ($v.failure -ceq 'HEALTH_TOKEN_IDENTITY')
}finally{
 foreach($f in @($stage,$target,$library)){if([IO.File]::Exists($f)){[IO.File]::Delete($f)}}
 [IO.Directory]::Delete($fixture)
}
Write-Host "PASS: $count health-token checks; real local DPAPI, mocked HTTP, worker/controller parsing. No runtime account or API changes."
