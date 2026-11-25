# Read-only projection of the newest delivery bundle; never return Docker output or credential material.
function Get-PaperDeliveryReport([string]$Directory='C:\MarketBrainData\Review') {
 $files=@(Get-ChildItem -LiteralPath $Directory -File | Where-Object {$_.Name -cmatch '^(paper-(delivery|publisher-preflight)-[0-9]{8}-[0-9]{6}-[a-f0-9]{12}|paytm-supervised-(login|deployment)-[a-f0-9]{32})\.json$'} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
 if($files.Count -ne 1 -or $files[0].Name -cnotmatch '^paper-(delivery|publisher-preflight)-'){return $null}
 $file=$files[0]
 if($file.Length -gt 2097152 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $bytes=[IO.File]::ReadAllBytes($file.FullName)
 if($bytes.Length -gt 2097152){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $v=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
 if($file.Name -cmatch '^paper-publisher-preflight-'){return Get-PublisherCatalogProjection $v $bytes $file.Name}
 if($v.version -cne 'PAPER_DELIVERY_BUNDLE_V1' -or $v.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'DELIVERY_REPORT_SCOPE_REJECTED'}
 $safe=[ordered]@{version=$v.version;runId=$v.runId;failurePresent=([bool]$v.failure)}
 foreach($n in @('status')){if($v.$n -cnotmatch '^[A-Z_]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$safe[$n]=$v.$n}
 foreach($n in @('syntheticDatabaseWritesPerformed','applicationDatabaseAccessed','actionExecutionEnabled')){if($v.$n -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$safe[$n]=$v.$n}
 $safe.elapsedSeconds=[double]$v.elapsedSeconds
 foreach($phase in @('prepare','recover')) {
  $safe[$phase]=$null;$p=$v.$phase;if($null -eq $p){continue}
  $s=[ordered]@{}
  foreach($n in @('version','status','phase','schema','httpTransport')){if([string]$p.$n -cnotmatch '^[A-Za-z0-9_-]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=$p.$n}
  foreach($n in @('applicationDatabaseAccessed','actionExecutionEnabled','syntheticDatabaseWritesPerformed')){if($p.$n -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=$p.$n}
  foreach($n in @('checkCount','failedCount','elapsedSeconds','providerCalls','telegramCalls','modelCalls','cashPaise','reservedCashPaise','ledgerRevision','orderCount','fillCount','decisionCount','deliveryCount','pendingCount','uncertainCount')){
   if($p.PSObject.Properties[$n]){if($p.$n -is [string] -or $p.$n -is [bool] -or $null -eq $p.$n){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=[decimal]$p.$n}
  }
  if(@($p.checks).Count -gt 64){throw 'DELIVERY_REPORT_FIELD_REJECTED'}
  $s.checks=@($p.checks|ForEach-Object {if($_.name -cnotmatch '^[a-z0-9_]{1,100}$' -or $_.passed -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};@{name=$_.name;passed=$_.passed;elapsedMillis=[double]$_.elapsedMillis}})
  $safe[$phase]=$s
 }
 $safe.cleanup=@($v.cleanup|ForEach-Object {if($_.action -cnotmatch '^[A-Z_]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};@{action=$_.action}})
 $safe.manifest=[ordered]@{}
 foreach($p in $v.manifest.PSObject.Properties){if($p.Name -eq 'codeRevision'){if($p.Value -cnotmatch '^[a-f0-9]{40}$'){throw 'DELIVERY_MANIFEST_REJECTED'};$safe.manifest.codeRevision=$p.Value;continue};if($p.Name -in @('dockerExecutable','verificationImage','databaseImage')){continue};if($p.Name -cnotmatch '^(ops/windows|marketbrain-service)/[A-Za-z0-9/_.-]{1,200}$' -or $p.Value -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'DELIVERY_MANIFEST_REJECTED'};$safe.manifest[$p.Name]=$p.Value}
 return @{test='PAPER_DELIVERY_REPORT_COLLECTION';passed=$true;status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED';sourceFile=$file.Name;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));report=$safe;ordersEnabled=$false}
}

function Get-PublisherCatalogProjection($v,[byte[]]$bytes,[string]$name) {
 if($v.version -cne 'PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1' -or $v.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'CATALOG_SCOPE_REJECTED'}
 function Project($value) {
  $out=[ordered]@{}
  foreach($key in @('version','status','scope','stage','failureCode','schemaName','resolvedSchema','database','roleName','functionName','tableName','kind','failureType','sqlState')) {
   if($null -ne $value.$key){if([string]$value.$key -cnotmatch '^[A-Za-z0-9_:-]{1,150}$'){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=$value.$key}
  }
  foreach($key in @('readOnly','repeatableRead','unchangedSessionIdentity','superuser','createRole','createDatabase','replication','bypassRls','login','publicDatabaseCreate','publicDatabaseTemp','currentRoleCreate','currentRoleOwnerMembership','publicCreate','present','rowSecurity','forceRowSecurity','currentRoleSelect','publicSelect','publicWrite','securityDefiner','publicExecute','catalogListBoundReached','publisherActivated','connectionAttempted','applicationDatabaseWritesPerformed','applicationWriterActivated','actionExecutionEnabled','applicationRestartRequested','databaseWritesRequested','timedOut')) {
   if($null -ne $value.$key){if($value.$key -isnot [bool]){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=$value.$key}
  }
  foreach($key in @('databaseOid','serverVersionNumber','elapsedSeconds','providerCalls','telegramCalls','modelCalls','exitCode','stdoutCharacters','stderrCharacters')) {
   if($null -ne $value.$key){if($value.$key -is [string] -or $value.$key -is [bool]){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=[decimal]$value.$key}
  };return $out
 }
 $safe=Project $v;$safe.runId=$v.runId;$safe.failurePresent=[bool]$v.failure;$safe.revision=$v.revision
 if($null -ne $v.runtimeConfigurationMatched){if($v.runtimeConfigurationMatched -isnot [bool]){throw 'CATALOG_FIELD_REJECTED'};$safe.runtimeConfigurationMatched=$v.runtimeConfigurationMatched}
 if($null -ne $v.revision -and $v.revision -cnotmatch '^[a-f0-9]{40}$'){throw 'CATALOG_REVISION_REJECTED'}
 $safe.catalog=Project $v.catalog
 if(@($v.steps).Count -gt 12){throw 'CATALOG_STEP_BOUND_REJECTED'}
 $safe.steps=@($v.steps|Where-Object {$null -ne $_}|ForEach-Object {Project $_})
 foreach($key in @('session','schema','target')){$safe.catalog[$key]=Project $v.catalog.$key}
 foreach($key in @('tables','proposedRoleCollisions','writerFunctionCollisions','publicCreateSchemas','publicCallableDefiners')) {
  if(@($v.catalog.$key).Count -gt 21){throw 'CATALOG_BOUND_REJECTED'};$safe.catalog[$key]=@($v.catalog.$key|Where-Object {$null -ne $_}|ForEach-Object {Project $_})
 }
 $safe.catalog.installationBlockers=@($v.catalog.installationBlockers|Where-Object {$null -ne $_}|ForEach-Object {if($_ -cnotmatch '^[A-Za-z0-9_:]{1,150}$'){throw 'CATALOG_BLOCKER_REJECTED'};$_})
 $safe.cleanup=Project $v.cleanup;$safe.manifest=[ordered]@{}
 foreach($p in $v.manifest.PSObject.Properties){if($p.Name -cnotmatch '^(compose\.paper-writer-preflight\.yaml|(?:ops/windows|marketbrain-service)/[A-Za-z0-9/_.-]{1,200})$' -or $p.Value -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'CATALOG_MANIFEST_REJECTED'};$safe.manifest[$p.Name]=$p.Value}
 if(@($safe.steps|Where-Object {$_.stage -eq 'configuration' -and $_.timedOut}).Count){$safe.dockerProbe=Get-PublisherDockerProbe}
 return @{test='PAPER_PUBLISHER_CATALOG_COLLECTION';passed=$true;status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED';sourceFile=$name;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));report=$safe;ordersEnabled=$false}
}
function Get-PublisherDockerProbe {
 $rows=@();$d=@(Get-Command docker.exe -CommandType Application -ErrorAction SilentlyContinue)
 if(-not $d.Count){return @{available=$false;checks=@()}}
 foreach($a in @(@('compose','version','--short'),@('version','--format','{{.Server.Version}}'))) {
  $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$d[0].Source;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  foreach($s in $a){[void]$p.StartInfo.ArgumentList.Add($s)}
  $w=[Diagnostics.Stopwatch]::StartNew()
  try{[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$done=$p.WaitForExit(20000)
   if(-not $done){$p.Kill($true);[void]$p.WaitForExit(3000)}
   $drained=$o.Wait(3000) -and $e.Wait(3000)
   $rows+=@{stage=($a[0]+'-version');timedOut=(-not $done);exitCode=$(if($done){$p.ExitCode}else{-999});elapsedSeconds=$w.Elapsed.TotalSeconds;outputDrained=$drained}
  }catch{$rows+=@{stage=($a[0]+'-version');probeFailed=$true}}
  finally{try{if(-not $p.HasExited){$p.Kill($true)}}catch{};$p.Dispose()}
 };return @{available=$true;checks=$rows;configurationRead=$false;databaseAccessed=$false}
}
