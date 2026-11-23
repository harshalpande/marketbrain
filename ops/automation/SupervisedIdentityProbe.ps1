# Public master plus existing saved-universe endpoint. No broker login or writes.
function Invoke-SupervisedIdentityProbe {
 $r=[ordered]@{test='PROVIDER_AND_SAVED_UNIVERSE_IDENTITY';passed=$false;ordersEnabled=$false;currentMembershipVerified=$false;providerIsinVerified=$false;failure=$null}
 try{
  $m=Get-PaytmQuoteMapping -Symbol RELIANCE
  $u=Invoke-SupervisedUniverseProbe
  if(-not $u.passed -or $u.universeMatch.symbol -cne $m.symbol -or $m.exchange -cne 'NSE' -or $m.series -cne 'EQ' -or $m.instrumentType -cne 'ES'){throw 'IDENTITY_CORROBORATION_FAILED'}
  # Explicit fields only: no raw CSV, local token, or unknown provider values.
  if($m.symbol -cne 'RELIANCE' -or [string]$m.securityId -cnotmatch '^[1-9][0-9]{0,7}$' -or $m.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'IDENTITY_MAPPING_REJECTED'}
  $r.mapping=@{symbol=$m.symbol;securityId=[int]$m.securityId;exchange='NSE';series='EQ';sha256=$m.sha256;source='PAYTM_PUBLIC_EQUITY_MASTER'}
  $r.savedUniverse=$u.universeMatch
  $r.passed=$true;$r.status='SYMBOL_CORROBORATED_FULL_IDENTITY_PENDING'
 }catch{$r.status='REVIEW_REQUIRED';$r.failure='IDENTITY_PROBE_FAILED'}
 return $r
}
