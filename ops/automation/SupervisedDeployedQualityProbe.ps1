function Invoke-SupervisedDeployedQualityProbe {
 $r=@{test='COPIED_DEPLOYED_QUOTE_QUALITY';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;applicationChanged=$false;failure=$null;cleanupPassed=$false}
 $dir=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
 function Invoke-QualityNative([string]$Exe,[string[]]$Arguments,[int]$Seconds=60){
  $p=[Diagnostics.Process]::new();$p.StartInfo=[Diagnostics.ProcessStartInfo]::new();$p.StartInfo.FileName=$Exe
  $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  foreach($a in $Arguments){$p.StartInfo.ArgumentList.Add($a)}
  try{
   $null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
   if(-not $p.WaitForExit($Seconds*1000)){try{$p.Kill($true)}catch{};throw 'QUALITY_NATIVE_TIMEOUT'}
   if($p.ExitCode -ne 0){$r.nativeExitCode=$p.ExitCode;throw 'QUALITY_NATIVE_FAILED'}
   $text=$o.GetAwaiter().GetResult();$null=$e.GetAwaiter().GetResult()
   if($text.Length -gt 16384){throw 'QUALITY_OUTPUT_TOO_LARGE'}
   return $text.Trim()
  }finally{$p.Dispose()}
 }
 try{
  $r.stage='RESOLVE_TOOLS'
  $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $javac=(Get-Command javac.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $java=Join-Path (Split-Path $javac -Parent) 'java.exe'
  if(-not (Test-Path -LiteralPath $java)){throw 'QUALITY_JAVA_MISSING'}
  $id=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running') 15
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'QUALITY_APPLICATION_NOT_UNIQUE'}
  $r.stage='COPY_DEPLOYED_ARTIFACT'
  $hash=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','exec',$id,'sha256sum','/app/app.jar') 15
  if($hash -cnotmatch '^([a-f0-9]{64})\s+/app/app.jar$'){throw 'QUALITY_ARTIFACT_HASH_INVALID'}
  $r.artifactSha256=$Matches[1]
  $parent=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
  $dir=Join-Path $parent ('quote-quality-'+[guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Path $dir -ErrorAction Stop
  $artifact=Join-Path $dir 'application.jar'
  $null=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','cp',($id+':/app/app.jar'),$artifact)
  if((Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant() -cne $r.artifactSha256){throw 'QUALITY_COPY_HASH_MISMATCH'}
  $r.stage='COMPILE_ISOLATED_PROBE'
  $source=Join-Path $dir 'DeployedQuoteQualityProbe.java'
  [IO.File]::WriteAllText($source,$script:deployedQualitySource,[Text.UTF8Encoding]::new($false))
  $null=Invoke-QualityNative $javac @('-J-Xmx128m','--release','21','-encoding','UTF-8','-d',$dir,$source)
  $r.stage='EXECUTE_SYNTHETIC_CASES'
  $v=(Invoke-QualityNative $java @('-Xmx128m','-cp',$dir,'DeployedQuoteQualityProbe',$artifact) 30)|ConvertFrom-Json
  if($v.passed -ne $true -or $v.ordersEnabled -ne $false -or $v.networkCalls -ne 0 -or $v.simulatedHttpCalls -ne 25 -or @($v.checks).Count -ne 25 -or $v.assessorSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'QUALITY_RESULTS_REJECTED'}
  $r.scope='COPIED_DEPLOYED_CLIENT_ASSESSOR_SIMULATED_HTTP_NATIVE_JVM';$r.assessorSha256=$v.assessorSha256
  $r.checks=@($v.checks|ForEach-Object {
   if($_.name -cnotmatch '^[A-Za-z0-9]{1,40}$' -or $_.expected -cnotmatch '^[A-Z_]{1,60}$' -or $_.actual -cnotmatch '^[A-Z_]{1,60}$' -or $_.passed -ne $true){throw 'QUALITY_CASE_REJECTED'}
   @{name=$_.name;expected=$_.expected;actual=$_.actual;passed=$true}
  })
  $r.stage='VERIFY_UNCHANGED'
  $after=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','exec',$id,'sha256sum','/app/app.jar') 15
  if($after -cne $hash){throw 'QUALITY_ARTIFACT_CHANGED'}
  $r.passed=$true;$r.stage='COMPLETE'
 }catch{$r.failure=if($_.Exception.Message -cmatch '^QUALITY_[A-Z_]+$'){$_.Exception.Message}else{'QUALITY_PROBE_FAILED'};$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 finally{
  if($dir){try{
   $full=[IO.Path]::GetFullPath($dir);$allowed=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'))+[IO.Path]::DirectorySeparatorChar
   if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -cnotmatch '^quote-quality-[a-f0-9]{32}$'){throw 'QUALITY_CLEANUP_PATH'}
   Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop;$r.cleanupPassed=$true
  }catch{$r.passed=$false;$r.cleanupFailure='QUALITY_TEMP_CLEANUP_FAILED'}}
  $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 }
 return $r
}
