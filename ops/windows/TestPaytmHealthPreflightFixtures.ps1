#Requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmHealthDeploymentPreflight.ps1')
Add-Type -AssemblyName System.IO.Compression
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-health-preflight-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $work
$source=Join-Path $work 'migrations';$null=New-Item -ItemType Directory $source
[IO.File]::WriteAllText((Join-Path $source 'V1__fixture.sql'),"select 1;`r`n")
function New-MigrationJar([string]$Name,[string]$Text){
 $path=Join-Path $work ([guid]::NewGuid().ToString('N')+'.jar');$f=[IO.File]::Create($path)
 $z=[IO.Compression.ZipArchive]::new($f,[IO.Compression.ZipArchiveMode]::Create)
 try{$e=$z.CreateEntry('BOOT-INF/classes/db/migration/'+$Name);$writer=[IO.StreamWriter]::new($e.Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write($Text)}finally{$writer.Dispose()}}finally{$z.Dispose();$f.Dispose()}
 return $path
}
$count=0
foreach($spec in @(@('V1__fixture.sql',"select 1;`n",$true),@('V1__fixture.sql',"select 2;`n",$false),@('V2__added.sql',"select 1;`n",$false))){
 $jar=New-MigrationJar $spec[0] $spec[1];$v=Compare-PaytmPackagedMigrations $jar $source
 if($v.matched -ne $spec[2]){throw 'Migration fixture'};$count++
}
$rejected=$false
try{$null=Compare-PaytmPackagedMigrations (New-MigrationJar '../escape.sql' 'bad') $source}catch{$rejected=$true}
if(-not $rejected){throw 'Archive path not rejected'};$count++
$src=Get-Content (Join-Path $PSScriptRoot 'TestPaytmHealthDeploymentPreflight.ps1') -Raw
foreach($name in @('PaytmApplicationRoute.ps1','PaytmHealthDeploymentPreflight.ps1')){$src=$src.Replace(". (Join-Path `$PSScriptRoot '$name')",'')}
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$e=Join-Path $work 'evidence.json';'{}'|Set-Content $e
$src=$src.Replace('C24D4B26B4A85CAF760F0BB05E7E9DD8DC13B664888E4E7DB88DD61D579F8235',(Get-FileHash $e).Hash)
function Get-Command {param($Name,$CommandType,$ErrorAction) @{Source='mock-docker'}}
function Get-PaytmApplicationContainer {
 [pscustomobject]@{Id=('a'*64);Image=('sha256:'+('b'*64));State=@{StartedAt='fixture'};Config=@{Labels=@{'com.docker.compose.project'='fixture'};Env=@('MARKETBRAIN_PAYTM_ENABLED=false','MARKETBRAIN_PAYTM_ACCESS_TOKEN=','MARKETBRAIN_PAPER_READ_TOKEN=SECRET_FIXTURE_TOKEN','MARKETBRAIN_PAPER_REVIEW_DATABASE_OID=1')};Mounts=@(@{Destination='/run/secrets/paper-approval.key';Source='C:/fixture/key'},@{Destination='/marketbrain-review';Source='C:/fixture/review'})}
}
function ConvertTo-PaperRuntimeEnvironment($Entries){$m=@{};foreach($e in $Entries){$a=$e.Split('=',2);$m[$a[0]]=$a[1]};return $m}
function ConvertTo-PaperHostMount($Path){$Path}
function Assert-PaytmWriterLocked {if($script:scenario -eq 'writerunlocked'){throw 'HEALTH_PREFLIGHT_WRITER_UNLOCKED'}}
function Read-PaytmHealthPreflightAccount($Token){$script:reads++;if($Token -cne 'SECRET_FIXTURE_TOKEN'){throw 'Token missing'};if($script:scenario -eq 'accountdrift' -and $script:reads -gt 1){'changed'}else{'baseline'}}
function Invoke-PaytmPrivateDocker($Arguments,$Phase,$Limit=30){
 switch($Arguments[0]){
  'context'{if($Arguments[1] -eq 'show'){'fixture'}else{'npipe://fixture'}}
  'image'{if($Arguments[1] -cne 'inspect'){throw 'Mutation'};'sha256:'+('b'*64)}
  'cp'{if($Arguments[1] -cne (('a'*64)+':/app/app.jar')){throw 'Copy direction'};[IO.File]::WriteAllText($Arguments[2],'fixture');''}
  'compose'{if($Arguments[-3] -cne 'config' -or $Arguments[-2] -cne '--format' -or $Arguments[-1] -cne 'json'){throw 'Mutation'};'{}'}
  default{throw 'Unexpected Docker operation'}
 }
}
function Compare-PaytmPackagedMigrations($Jar,$Directory){@{matched=($script:scenario -ne 'migrationdiff');packagedCount=1;sourceCount=1;differences=@()}}
function ConvertFrom-PaytmPrivateJson($Text){$Text|ConvertFrom-Json}
function Assert-PaperRuntimeCompose($Plan,$Before,$Oid,$Image){if($script:scenario -eq 'composefail'){throw 'HEALTH_PREFLIGHT_COMPOSE_DRIFT'}}
function Assert-PaperRuntimePreserved($Before,$After){}
$original=[Environment]::GetEnvironmentVariable('MARKETBRAIN_PAPER_READ_TOKEN','Process')
foreach($script:scenario in @('pass','migrationdiff','composefail','accountdrift','writerunlocked')){
 $script:reads=0;$out=Join-Path $work $script:scenario;$errorText=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$errorText=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$r=$raw|ConvertFrom-Json
 if($raw.Contains('SECRET_FIXTURE_TOKEN')){throw 'Secret leaked'}
 if($script:scenario -eq 'pass'){if($errorText -or $r.status -cne 'HEALTH_DEPLOYMENT_PREFLIGHT_PASSED_ACTIVATION_PENDING'){throw "Pass failed: $errorText"}}else{if(-not $errorText -or $r.status -cne 'REVIEW_REQUIRED'){throw 'Missing failure'}}
 if(-not $r.temporaryJarRemoved -or $r.applicationChanged -or $r.credentialsProvisioned -or $r.ordersEnabled){throw 'Authority/cleanup'}
 if([string][Environment]::GetEnvironmentVariable('MARKETBRAIN_PAPER_READ_TOKEN','Process') -cne [string]$original){throw 'Environment not restored'}
 $count++
}
Write-Host "PASS: $count migration/controller fixtures; no Docker, provider or application calls."
