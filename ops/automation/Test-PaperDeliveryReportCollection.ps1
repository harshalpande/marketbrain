#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/Collect-PaperDeliveryReport.ps1"
$dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-delivery-collect-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$file=Join-Path $dir 'paper-delivery-20261125-120000-aaaaaaaaaaaa.json'
try {
 $v=@{version='PAPER_DELIVERY_BUNDLE_V1';runId='a'*32;status='FAILED';failure='PRIVATE_VALUE';elapsedSeconds=2;syntheticDatabaseWritesPerformed=$true;applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;prepare=$null;recover=$null;cleanup=@(@{action='PRESERVED_STOP_REQUESTED';detail='PRIVATE_VALUE'});manifest=@{'ops/windows/TestPaperPersistenceBundle.ps1'=('A'*64);codeRevision=('a'*40);dockerExecutable='PRIVATE_VALUE';verificationImage='PRIVATE_VALUE';databaseImage='PRIVATE_VALUE'};events=@('PRIVATE_VALUE')}
 $v|ConvertTo-Json -Depth 7|Set-Content $file
 $r=Get-PaperDeliveryReport $dir
 if(-not $r.passed -or -not $r.report.failurePresent -or ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE_VALUE')){throw 'FAILED_REPORT_PROJECTION'}
 if($r.sha256 -ne (Get-FileHash $file).Hash){throw 'HASH_MISMATCH'}
 $v.prepare=@{version='PAPER_DELIVERY_REVIEW_V1';status='ISOLATED_DELIVERY_CHECKS_PASSED';phase='--prepare';schema=('paper_verify_'+('a'*32));httpTransport='FAKE_NO_NETWORK';applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;syntheticDatabaseWritesPerformed=$true;checkCount=1;failedCount=0;checks=@(@{name='batch_test';passed=$true;elapsedMillis=1;detail='PRIVATE_VALUE'})}
 $v|ConvertTo-Json -Depth 7|Set-Content $file
 $r=Get-PaperDeliveryReport $dir
 if($r.report.prepare.checks.Count -ne 1 -or ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE_VALUE')){throw 'PHASE_PROJECTION'}
 $v.prepare.checks[0].passed='true';$v|ConvertTo-Json -Depth 7|Set-Content $file
 $rejected=$false;try{Get-PaperDeliveryReport $dir|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'MALFORMED_ACCEPTED'}
 $newer=Join-Path $dir ('paytm-supervised-login-'+('b'*32)+'.json');'{}'|Set-Content $newer
 (Get-Item $newer).LastWriteTimeUtc=[DateTime]::UtcNow.AddMinutes(1)
 if($null -ne (Get-PaperDeliveryReport $dir)){throw 'OLDER_DELIVERY_SELECTED'}
 $catalog=Join-Path $dir 'paper-publisher-preflight-20261125-130000-bbbbbbbbbbbb.json'
 $c=@{version='PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1';runId='b'*32;revision='a'*40;status='CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED';elapsedSeconds=1;failure=$null;steps=@('PRIVATE_VALUE');catalog=@{version='PAPER_PUBLISHER_PREFLIGHT_V1';publisherActivated=$false;target=@{database='marketbrain';databaseOid=42;password='PRIVATE_VALUE'};installationBlockers=@('PROPOSED_ROLE_NAME_COLLISION_DO_NOT_ADOPT');tables=@(@{tableName='instrument';present=$true;extra='PRIVATE_VALUE'})};manifest=@{'compose.paper-writer-preflight.yaml'=('A'*64)};cleanup=@{exitCode=0;timedOut=$false;detail='PRIVATE_VALUE'}}
 $c|ConvertTo-Json -Depth 8|Set-Content $catalog
 (Get-Item $catalog).LastWriteTimeUtc=[DateTime]::UtcNow.AddMinutes(2)
 $r=Get-PaperDeliveryReport $dir
 if($r.test -ne 'PAPER_PUBLISHER_CATALOG_COLLECTION' -or $r.report.catalog.target.databaseOid -ne 42 -or ($r|ConvertTo-Json -Depth 9).Contains('PRIVATE_VALUE')){throw 'CATALOG_PROJECTION_FAILED'}
 if($r.sha256 -ne (Get-FileHash $catalog).Hash){throw 'CATALOG_HASH_MISMATCH'}
 $c.catalog.publisherActivated='false';$c|ConvertTo-Json -Depth 8|Set-Content $catalog
 (Get-Item $catalog).LastWriteTimeUtc=[DateTime]::UtcNow.AddMinutes(2)
 $rejected=$false;try{Get-PaperDeliveryReport $dir|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'CATALOG_MALFORMED_ACCEPTED'}
 $c.catalog=$null;$c.revision=$null;$c.failure='PRIVATE_VALUE';$c.status='STOPPED_REVIEW_REQUIRED';$c.manifest=@{}
 $c|ConvertTo-Json -Depth 8|Set-Content $catalog;(Get-Item $catalog).LastWriteTimeUtc=[DateTime]::UtcNow.AddMinutes(2)
 $r=Get-PaperDeliveryReport $dir
 if(-not $r.report.failurePresent -or ($r|ConvertTo-Json -Depth 9).Contains('PRIVATE_VALUE')){throw 'EARLY_FAILURE_PROJECTION_FAILED'}
 Write-Host 'PASS: delivery collection projection, hash, redaction, malformed rejection and newest selection.'
}finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue;if($catalog){Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue};if($newer){Remove-Item -LiteralPath $newer -Force -ErrorAction SilentlyContinue};Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue}
