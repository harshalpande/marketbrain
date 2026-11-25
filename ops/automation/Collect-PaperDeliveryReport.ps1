# Read-only projection of the newest delivery bundle; never return Docker output or credential material.
function Get-PaperDeliveryReport([string]$Directory='C:\MarketBrainData\Review') {
 $files=@(Get-ChildItem -LiteralPath $Directory -File | Where-Object {$_.Name -cmatch '^(paper-delivery-[0-9]{8}-[0-9]{6}-[a-f0-9]{12}|paytm-supervised-(login|deployment)-[a-f0-9]{32})\.json$'} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
 if($files.Count -ne 1 -or $files[0].Name -cnotmatch '^paper-delivery-'){return $null}
 $file=$files[0]
 if($file.Length -gt 2097152 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $bytes=[IO.File]::ReadAllBytes($file.FullName)
 if($bytes.Length -gt 2097152){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $v=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
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
 foreach($p in $v.manifest.PSObject.Properties){if($p.Name -cnotmatch '^(ops/windows|marketbrain-service)/[A-Za-z0-9/_.-]{1,200}$' -or $p.Value -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'DELIVERY_MANIFEST_REJECTED'};$safe.manifest[$p.Name]=$p.Value}
 return @{test='PAPER_DELIVERY_REPORT_COLLECTION';passed=$true;status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED';sourceFile=$file.Name;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));report=$safe;ordersEnabled=$false}
}
