#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedIdentityProbe.ps1"
$script:mode='pass'
function Get-PaytmQuoteMapping {param($Symbol)
 if($Symbol -cne 'RELIANCE'){throw 'Wrong symbol'}
 if($script:mode -eq 'download'){throw 'SECRET_ERROR'}
 return @{symbol='RELIANCE';securityId=2885;exchange='NSE';series='EQ';instrumentType='ES';sha256=('A'*64);secret='MUST_NOT_LEAVE'}
}
function Invoke-SupervisedUniverseProbe {
 return @{passed=($script:mode -ne 'missing');universeMatch=@{symbol=$(if($script:mode -eq 'mismatch'){'OTHER'}else{'RELIANCE'});snapshotMatched=$true;ordersEnabled=$false}}
}
foreach($case in @('pass','missing','mismatch','download')){
 $script:mode=$case;$r=Invoke-SupervisedIdentityProbe
 if($r.passed -ne ($case -eq 'pass')){throw "IDENTITY_FIXTURE_FAILED: $case"}
 if(($r|ConvertTo-Json -Depth 6) -match 'SECRET_ERROR|MUST_NOT_LEAVE'){throw 'IDENTITY_SECRET_LEAK'}
 if($r.currentMembershipVerified -or $r.providerIsinVerified -or $r.ordersEnabled){throw 'IDENTITY_OVERCLAIM'}
}
Write-Host 'IDENTITY_PROBE_4_FIXTURES_PASSED'
