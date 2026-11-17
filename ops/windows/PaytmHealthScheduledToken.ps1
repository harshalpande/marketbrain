# Definitions only. Never export the health token or ciphertext to evidence.
function Assert-HealthScheduledTokenPrerequisites([string]$ReportPath){
 if((Get-FileHash -LiteralPath $ReportPath).Hash -cne '957F45858B02613726FC3B54F38FEADCDC4C322E2FBD7A4D7481299F6D7D114C'){throw 'SCHEDULE_TOKEN_RECEIPT_MISMATCH'}
 $dir='C:\ProgramData\MarketBrainPaytmHealth\token-custody'
 $k=Get-HealthKeyContract
 $null=Read-PaytmHealthAccount
 $null=Assert-PaytmAccountPath $dir;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $dir) $k.sid
 foreach($n in @('library.ps1','health-token.dpapi','custody-state.json')){$null=Assert-PaytmAccountPath (Join-Path $dir $n);if(-not (Test-Path -LiteralPath (Join-Path $dir $n) -PathType Leaf)){throw 'SCHEDULE_TOKEN_FILE_MISSING'}}
 if((Get-FileHash -LiteralPath "$dir/library.ps1").Hash -cne 'C93B10DF35EBE8ED703D115CD192DAD13547CC30B35C7069B5EFEF396AB349DC'){throw 'SCHEDULE_TOKEN_LIBRARY_CHANGED'}
 $state=Read-PaytmRepairJson "$dir/custody-state.json" 4096
 if($state.version -ne 1 -or $state.runId -cne '88ebf8fdc3de4c158351e86df95e7217' -or $state.sid -cne $k.sid -or $state.purpose -cne 'DIAGNOSTIC_HEALTH_ONLY' -or $state.protection -cne 'DPAPI_CURRENT_USER' -or $state.taskInstalled -ne $false){throw 'SCHEDULE_TOKEN_MANIFEST_CHANGED'}
 $size=(Get-Item -LiteralPath "$dir/health-token.dpapi").Length
 if($size -lt 100 -or $size -gt 4096){throw 'SCHEDULE_TOKEN_CIPHER_SIZE'}
}
function Get-HealthScheduledTokenSource {
 @'
 $r.stage='TOKEN_AND_LOCAL_AUTHENTICATION';$token=$null
 try{
  $tokenRoot='C:\ProgramData\MarketBrainPaytmHealth\token-custody'
  if((Get-FileHash -LiteralPath ($tokenRoot+'\library.ps1')).Hash -cne 'C93B10DF35EBE8ED703D115CD192DAD13547CC30B35C7069B5EFEF396AB349DC'){throw 'SCHEDULE_TOKEN_LIBRARY_CHANGED'}
  . ([scriptblock]::Create([IO.File]::ReadAllText($tokenRoot+'\library.ps1')))
  if((Get-Item -LiteralPath ($tokenRoot+'\health-token.dpapi')).Length -gt 4096){throw 'SCHEDULE_TOKEN_CIPHER_SIZE'}
  $token=Unprotect-HealthToken ([IO.File]::ReadAllBytes($tokenRoot+'\health-token.dpapi'))
  $r['tokenDecrypted']=$true
  $r['applicationBootId']=Test-HealthTokenAuthority $token
  $r['tokenAuthenticated']=$true;$r['applicationLocked']=$true
 }finally{$token=$null}
'@
}
function Assert-HealthScheduledTokenResult($Worker){
 foreach($n in @('tokenDecrypted','tokenAuthenticated','applicationLocked')){
  if($Worker.$n -isnot [bool] -or -not $Worker.$n){throw 'SCHEDULE_TOKEN_PROOF_MISSING'}
 }
 if($Worker.applicationBootId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'SCHEDULE_TOKEN_BOOT_INVALID'}
}
