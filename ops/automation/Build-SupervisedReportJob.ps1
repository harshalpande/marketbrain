#Requires -Version 7.2
param([switch]$Check)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Collect-SupervisedLoginReport.ps1'))
$probe=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedBoundaryProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedGatewayObservation.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedGatewayStartupProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedUniverseProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedLifecycleProbe.ps1'))
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../windows/PaytmQuoteBatch.ps1'))
$probe+="`n"+([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../windows/PaytmQuoteMapping.ps1')) -replace '(?m)^#Requires[^\r\n]*','')
$probe+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SupervisedIdentityProbe.ps1'))
$fixtures=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../windows/TestPaytmQuoteBatch.ps1'))
$fixtures=($fixtures -split '\r?\n'|Where-Object {$_ -notmatch '^#Requires|^\. |^Write-Host'}) -join "`n"
$probe+="`nfunction Invoke-SupervisedQuoteFixtures {`ntry {`n"+$fixtures+@'

 return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$true;fixtureCount=8;brokerCalls=0;ordersEnabled=$false}
}catch{return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$false;fixtureCount=8;failure='QUOTE_FIXTURE_FAILED';brokerCalls=0;ordersEnabled=$false}}
}
'@
$insertion=$probe+@'

if($Mode -eq 'FailureFixture'){
 $boundary=Invoke-SupervisedBoundaryProbe
 $quality=Invoke-SupervisedQuoteFixtures
 $identity=Invoke-SupervisedIdentityProbe
 $batch=@{test='BOUNDARY_QUOTE_VALIDATION_AND_IDENTITY';passed=($boundary.passed -and $quality.passed -and $identity.passed);boundary=$boundary;quoteFixtures=$quality;identity=$identity;ordersEnabled=$false}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $batch.passed){exit 1}
 exit 0
}
if($Mode -eq 'Apply'){
 $universe=Invoke-SupervisedUniverseProbe
 [IO.File]::WriteAllText($ResultPath,($universe|ConvertTo-Json -Depth 6))
 if(-not $universe.passed){exit 1}
 $lifecycle=Invoke-SupervisedLifecycleProbe
 $batch=@{test='SUPERVISED_UNIVERSE_AND_LIFECYCLE';passed=$lifecycle.passed;ordersEnabled=$false;universe=$universe;lifecycle=$lifecycle}
 if($lifecycle.passed -and $lifecycle.finalLocked){$batch.gatewayStartup=Invoke-SupervisedGatewayStartupProbe;$batch.passed=$batch.gatewayStartup.passed}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $lifecycle.passed){exit 1}
 exit 0
}

'@
$source=$source.Replace("`$ErrorActionPreference='Stop'","`$ErrorActionPreference='Stop'"+"`n"+$insertion)
$target=Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'
if($Check){if([IO.File]::ReadAllText($target).Replace("`r`n","`n") -cne $source.Replace("`r`n","`n")){throw 'SUPERVISED_REPORT_ARTIFACT_DRIFT'}}
else{[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))}
