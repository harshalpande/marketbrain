#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmQuoteMapping.ps1"
$header='"security_id","symbol","exchange","series","segment","instrument_type"'
$row='"2885","RELIANCE","NSE","EQ","E","ES"'
$csv=$header+"`n"+$row
$hash='A'*64
$m=Resolve-PaytmQuoteMappingFromCsv $csv RELIANCE $hash
if($m.securityId -ne 2885 -or $m.localUniverseVerified -ne $false){throw 'MAPPING_FIXTURE_FAILED'}
$bad=@(($csv+"`n"+$row),$csv.Replace('NSE','BSE'),$csv.Replace('EQ','BE'),$csv.Replace('ES','FUT'),$csv.Replace('2885','oops'),$csv.Replace('security_id','other'),($csv+"`n"+$row.Replace('RELIANCE','OTHER')))
foreach($fixture in $bad){
 $rejected=$false
 try{$null=Resolve-PaytmQuoteMappingFromCsv $fixture RELIANCE $hash}catch{$rejected=$true}
 if(-not $rejected){throw 'MAPPING_NEGATIVE_NOT_REJECTED'}
}
Write-Host 'PAYTM_MAPPING_8_FIXTURES_PASSED'
