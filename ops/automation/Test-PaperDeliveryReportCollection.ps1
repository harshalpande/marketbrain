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
 Write-Host 'PASS: delivery collection projection, hash, redaction, malformed rejection and newest selection.'
}finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue;if($newer){Remove-Item -LiteralPath $newer -Force -ErrorAction SilentlyContinue};Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue}
