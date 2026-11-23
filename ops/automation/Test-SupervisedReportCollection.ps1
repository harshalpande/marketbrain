#Requires -Version 7.2
$ErrorActionPreference='Stop'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-report-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $dir
try {
 $source=[IO.File]::ReadAllText("$PSScriptRoot/Collect-SupervisedLoginReport.ps1").Replace('C:\MarketBrainData\Review',$dir)
 $script=[scriptblock]::Create($source)
 $run='a'*32;$file=Join-Path $dir "paytm-supervised-login-$run.json";$output=Join-Path $dir 'result.json'
 $fixture=@{version=1;runId=$run;ordersEnabled=$false;status='SUPERVISED_QUOTE_CAPTURED_FRESHNESS_PENDING';stage='QUOTES';readAccessVerified=$true;quotesTested=$true;windowsClockGate=$false;vpsAccuracyAssumed=$true;cleanup=@('APPLICATION_LOCKED','GATEWAY_STOPPED_DISABLED');elapsedSeconds=123;quoteSamples=@(@{status='STALE_QUOTE';securityId=3456;lastPrice=423.75;rawTradeTime=1479700000;ageMilliseconds=20000;fresh=$false;mappingVerified=$false;ordersEnabled=$false;secret='MUST_NOT_LEAVE'})}
 [IO.File]::WriteAllText($file,($fixture|ConvertTo-Json -Depth 6))
 $fixture.quoteMapping=@{symbol='RELIANCE';securityId=2885;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=('A'*64);localUniverseVerified=$false;secret='MUST_NOT_LEAVE'}
 $fixture.universeMatch=@{symbol='RELIANCE';status='LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED';snapshotId='11111111-1111-1111-1111-111111111111';observedOn='2026-09-18';isin='INE002A01018';instrumentId=1;snapshotMatched=$true;currentMembershipVerified=$false;providerIsinVerified=$false;ordersEnabled=$false;secret='MUST_NOT_LEAVE'}
 $fixture.sessionExpiry=@{status='AUTHENTICATED_EXPIRY_PASSED_RELOGIN_RESTART_PENDING';failure=$null;elapsedSeconds=900;passed=$true;authenticatedBeforeWait=$true;quoteLimitRejected=$true;expiryObserved=$true;postExpiryQuoteRejected=$true;ordersEnabled=$false;secret='MUST_NOT_LEAVE'}
 $fixture.sessionRestart=@{status='AUTHENTICATED_RESTART_PASSED_RELOGIN_PENDING';failure=$null;elapsedSeconds=30;passed=$true;authenticatedBeforeRestart=$true;restartAttempted=$true;sameContainer=$true;startChanged=$true;lockedAfterRestart=$true;quoteRejected=$true;ordersEnabled=$false;secret='MUST_NOT_LEAVE'}
 $fixture.callbackReplay=@{requested=$true;verified=$true;exchangeAttempts=1;secret='MUST_NOT_LEAVE'}
 $fixture.identityBinding=@{status='IDENTITY_BOUND_FRESH_QUOTE';reviewEligible=$true;ordersEnabled=$false;secret='MUST_NOT_LEAVE';identity=@{symbol='RELIANCE';securityId=2885;instrumentId=1202;isin='INE002A01018';snapshotId=('a'*8+'-aaaa-aaaa-aaaa-'+('a'*12));snapshotDate='2026-09-02';providerSha256=('A'*64);constituentSha256=('B'*64);basis='UNIQUE_NSE_EQ_SYMBOL_BRIDGE';membershipScope='LATEST_PUBLISHED_FILE';providerIsinVerified=$false;secret='MUST_NOT_LEAVE'}}
 $fixture.transportFailure=@{status='TRANSPORT_FAILURE_PASSED_RELOGIN_PENDING';failure=$null;elapsedSeconds=5;passed=$true;gatewayStopped=$true;transportRejected=$true;sessionLocked=$true;subsequentQuoteRejected=$true;ordersEnabled=$false;secret='MUST_NOT_LEAVE'}
 $fixture.quoteBatch=@{status='FRESHNESS_PENDING';passed=$false;strictFreshRequired=$true;sampleCount=3;freshCount=0;staleCount=3;missingCount=0;securityId=2885;ordersEnabled=$false;secret='MUST_NOT_LEAVE'}
 [IO.File]::WriteAllText($file,($fixture|ConvertTo-Json -Depth 6))
 & $script -ResultPath $output -Mode Observe
 $text=[IO.File]::ReadAllText($output);$r=$text|ConvertFrom-Json
 if(-not $r.passed -or $r.report.quoteSamples.Count -ne 1 -or $r.report.quoteSamples[0].status -ne 'STALE_QUOTE' -or $text.Contains('MUST_NOT_LEAVE')){throw 'QUOTE_REPORT_FIXTURE_FAILED'}
 if($r.report.quoteMapping.securityId -ne 2885 -or $r.report.quoteMapping.symbol -ne 'RELIANCE'){throw 'MAPPING_REPORT_FIXTURE_FAILED'}
 if(-not $r.report.universeMatch.snapshotMatched -or $r.report.universeMatch.isin -ne 'INE002A01018'){throw 'UNIVERSE_REPORT_FIXTURE_FAILED'}
 if(-not $r.report.sessionExpiry.postExpiryQuoteRejected -or -not $r.report.sessionExpiry.passed){throw 'EXPIRY_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('sessionExpiry')
 if(-not $r.report.sessionRestart.quoteRejected -or -not $r.report.sessionRestart.passed){throw 'RESTART_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('sessionRestart')
 if(-not $r.report.callbackReplay.verified -or $r.report.callbackReplay.exchangeAttempts -ne 1){throw 'REPLAY_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('callbackReplay')
 if(-not $r.report.identityBinding.reviewEligible -or $r.report.identityBinding.identity.securityId -ne 2885){throw 'IDENTITY_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('identityBinding')
 if(-not $r.report.transportFailure.passed -or -not $r.report.transportFailure.subsequentQuoteRejected){throw 'TRANSPORT_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('transportFailure')
 if($r.report.quoteBatch.passed -or $r.report.quoteBatch.staleCount -ne 3 -or -not $r.report.quoteBatch.strictFreshRequired){throw 'BATCH_REPORT_FIXTURE_FAILED'}
 $fixture.Remove('quoteBatch')
 $fixture.Remove('quoteMapping')
 $fixture.Remove('universeMatch')
 $fixture.Remove('quoteSamples');$fixture.quotesTested=$false
 [IO.File]::WriteAllText($file,($fixture|ConvertTo-Json -Depth 6))
 & $script -ResultPath $output -Mode Observe
 if(-not ((Get-Content $output -Raw|ConvertFrom-Json).passed)){throw 'LOGIN_COMPATIBILITY_FAILED'}
 Write-Host 'SUPERVISED_REPORT_QUOTE_AND_LOGIN_FIXTURES_PASSED'
}finally{
 # Unique generated fixture directory, created above; no application files are touched.
 if((Split-Path $dir -Leaf) -notmatch '^mb-report-fixture-[a-f0-9]{32}$'){throw 'FIXTURE_PATH_REJECTED'}
 $resolved=[IO.Path]::GetFullPath($dir)
 $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_PATH_REJECTED'}
 Remove-Item -LiteralPath $dir -Recurse -Force
}
