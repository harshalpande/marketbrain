# Read-only helpers. Never print JAR contents, inspect/config JSON or account tokens.
function Get-PaytmMigrationDigest([string]$Text) {
 $bytes=[Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n","`n"))
 return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
function Compare-PaytmPackagedMigrations([string]$Jar,[string]$Directory) {
 Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
 $stream=[IO.File]::OpenRead($Jar);$zip=$null;$packaged=@{};$source=@{}
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
  foreach($entry in $zip.Entries){
   if(-not $entry.FullName.StartsWith('BOOT-INF/classes/db/migration/')){continue}
   if($entry.FullName.EndsWith('/')){continue}
   $name=$entry.FullName.Substring('BOOT-INF/classes/db/migration/'.Length)
   if($name -cnotmatch '^[A-Za-z0-9_.-]+\.sql$' -or $entry.Length -gt 1048576 -or $packaged.ContainsKey($name)){throw 'HEALTH_PREFLIGHT_MIGRATION_ARCHIVE_INVALID'}
   $reader=[IO.StreamReader]::new($entry.Open(),[Text.Encoding]::UTF8,$true)
   try{$packaged[$name]=Get-PaytmMigrationDigest $reader.ReadToEnd()}finally{$reader.Dispose()}
  }
 }finally{if($zip){$zip.Dispose()};$stream.Dispose()}
 foreach($file in Get-ChildItem -LiteralPath $Directory -File -Recurse){
  if($file.DirectoryName -ine [IO.Path]::GetFullPath($Directory) -or $file.Name -cnotmatch '^[A-Za-z0-9_.-]+\.sql$' -or $file.Length -gt 1048576){throw 'HEALTH_PREFLIGHT_MIGRATION_SOURCE_INVALID'}
  $source[$file.Name]=Get-PaytmMigrationDigest ([IO.File]::ReadAllText($file.FullName))
 }
 $differences=@(foreach($name in @(@($packaged.Keys)+@($source.Keys)|Sort-Object -Unique)){
  if(-not $packaged.ContainsKey($name) -or -not $source.ContainsKey($name) -or $packaged[$name] -cne $source[$name]){$name}
 })
 [pscustomobject]@{matched=($source.Count -gt 0 -and $packaged.Count -eq $source.Count -and $differences.Count -eq 0);packagedCount=$packaged.Count;sourceCount=$source.Count;differences=$differences;comparison='UTF8_TEXT_CRLF_NORMALIZED_NOT_DATABASE_SCHEMA_CHECK'}
}
function Read-PaytmHealthPreflightAccount([string]$Token) {
 try{
  $r=Invoke-WebRequest 'http://127.0.0.1:8080/api/v1/paper/account/overview' -Headers @{'X-MarketBrain-Paper-Read-Token'=$Token} -NoProxy -TimeoutSec 15 -MaximumRedirection 0 -SkipHttpErrorCheck
  if($r.StatusCode -ne 200 -or ($r.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'contract'}
  $v=$r.Content|ConvertFrom-Json;Assert-PaperAccountOverview $v
  if($v.ledger.status -cne 'ATTACHED_READ_ONLY'){throw 'ledger'}
  Get-PaytmMigrationDigest (([ordered]@{account=$v.account;ledger=$v.ledger;legacyOrders=$v.legacyOrdersPresent;legacyFills=$v.legacyFillsPresent})|ConvertTo-Json -Depth 6 -Compress)
 }catch{throw 'HEALTH_PREFLIGHT_ACCOUNT_READ_FAILED'}
}
