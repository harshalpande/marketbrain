#Requires -Version 7.2
function Resolve-PaytmQuoteMappingFromCsv {
 param([Parameter(Mandatory)][string]$Csv,[Parameter(Mandatory)][string]$Symbol,[Parameter(Mandatory)][string]$Sha256)
 if($Symbol -cnotmatch '^[A-Z0-9][A-Z0-9&-]{0,29}$' -or $Sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'SUPERVISED_MAPPING_INPUT_INVALID'}
 if([Text.Encoding]::UTF8.GetByteCount($Csv) -gt 4194304){throw 'SUPERVISED_MAPPING_TOO_LARGE'}
 $rows=@(ConvertFrom-Csv -InputObject $Csv -ErrorAction Stop)
 if($rows.Count -eq 0 -or $rows.Count -gt 30000){throw 'SUPERVISED_MAPPING_ROWS_INVALID'}
 foreach($name in @('security_id','symbol','exchange','series','segment','instrument_type')){
  if(-not $rows[0].PSObject.Properties[$name]){throw 'SUPERVISED_MAPPING_SCHEMA_INVALID'}
 }
 $matchingRows=@($rows|Where-Object {$_.symbol -ceq $Symbol -and $_.exchange -ceq 'NSE' -and $_.series -ceq 'EQ' -and $_.segment -ceq 'E' -and $_.instrument_type -ceq 'ES'})
 if($matchingRows.Count -ne 1 -or $matchingRows[0].security_id -cnotmatch '^[1-9][0-9]{0,7}$'){throw 'SUPERVISED_MAPPING_NOT_UNIQUE'}
 $id=$matchingRows[0].security_id
 if(@($rows|Where-Object {$_.exchange -ceq 'NSE' -and $_.security_id -ceq $id}).Count -ne 1){throw 'SUPERVISED_MAPPING_ID_CONFLICT'}
 return [ordered]@{symbol=$Symbol;securityId=[int]$id;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=$Sha256;localUniverseVerified=$false}
}
function Get-PaytmQuoteMapping {
 param([Parameter(Mandatory)][string]$Symbol)
 # Public reference data only. No broker credentials; no fallback URL or redirects.
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(25);$client.MaxResponseContentBufferSize=4194304
 $response=$null
 try {
  $response=$client.GetAsync('https://developer.paytmmoney.com/data/v1/scrips/equity_security_master.csv').GetAwaiter().GetResult()
  if([int]$response.StatusCode -ne 200){throw 'SUPERVISED_MAPPING_DOWNLOAD_FAILED'}
  $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  $csv=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
  Resolve-PaytmQuoteMappingFromCsv -Csv $csv -Symbol $Symbol -Sha256 $hash
 } catch {
  if($_.Exception.Message -cmatch '^SUPERVISED_MAPPING_[A-Z_]+$'){throw}
  throw 'SUPERVISED_MAPPING_DOWNLOAD_OR_PARSE_FAILED'
 } finally {if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}
