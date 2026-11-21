# Fixed saved-universe read. Only the existing local paper read token is read into
# process memory. No broker login, gateway changes, database writes or orders.
function Invoke-UniverseDocker([string[]]$Arguments) {
 $exe=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 foreach($arg in (@('--host','npipe:////./pipe/docker_engine')+$Arguments)){$info.ArgumentList.Add($arg)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$info
 try{
  $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(10000)){try{$p.Kill($true)}catch{};throw 'UNIVERSE_DOCKER_TIMEOUT'}
  if($p.ExitCode -ne 0){throw 'UNIVERSE_DOCKER_FAILED'}
  $value=$stdout.GetAwaiter().GetResult()
  if($value.Length -gt 4096){throw 'UNIVERSE_DOCKER_OUTPUT_REJECTED'}
  return $value.Trim()
 }finally{$p.Dispose()}
}
function Invoke-SupervisedUniverseProbe {
 $r=[ordered]@{version=1;test='SUPERVISED_SAVED_UNIVERSE_PROBE';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;failure=$null}
 $token=$null;$headers=$null
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'UNIVERSE_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'UNIVERSE_LOCAL_TOKEN_INVALID'}
  $headers=@{'X-MarketBrain-Paper-Read-Token'=$token;'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
  $v=Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/v1/paytm/supervised/universe-match' -Method Post -NoProxy -TimeoutSec 10 -MaximumRedirection 0 -Headers $headers -ContentType 'application/json' -Body '{"symbol":"RELIANCE"}'
  if($v.status -cnotmatch '^[A-Z_]{1,100}$' -or $v.ordersEnabled -ne $false -or $v.snapshotMatched -isnot [bool]){throw 'UNIVERSE_RESPONSE_INVALID'}
  $safe=[ordered]@{status=[string]$v.status;snapshotMatched=$v.snapshotMatched;ordersEnabled=$false}
  $patterns=@{symbol='^RELIANCE$';snapshotId='^[a-f0-9-]{36}$';observedOn='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';instrumentId='^[1-9][0-9]{0,18}$'}
  foreach($name in $patterns.Keys){if($v.PSObject.Properties[$name]){if([string]$v.$name -cnotmatch $patterns[$name]){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$v.$name}}
  foreach($name in @('currentMembershipVerified','providerIsinVerified')){if($v.PSObject.Properties[$name]){if($v.$name -isnot [bool] -or $v.$name){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$false}}
  $r.universeMatch=$safe
  $r.passed=($v.status -ceq 'LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED' -and $v.snapshotMatched -eq $true -and $v.symbol -ceq 'RELIANCE')
 }catch{$r.failure=if($_.Exception.Message -cmatch '^UNIVERSE_[A-Z_]+$'){$_.Exception.Message}else{'UNIVERSE_PROBE_FAILED'}}
 finally{$token=$null;$headers=$null}
 return $r
}
