#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmClockKeyPreparation.ps1')
# Reuse synthetic, non-decryptable key-format fixture builders only.
$fixture=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmGatewayKeyCustody.ps1'))
$builders=$fixture.Substring($fixture.IndexOf('function U32('),$fixture.IndexOf('$valid=FixtureKey')-$fixture.IndexOf('function U32('))
. ([scriptblock]::Create($builders))
$bytes=[Convert]::FromBase64String((Get-PaytmKeyContract).publicBlob);$bytes[-1]=$bytes[-1] -bxor 7
$script:blob=[Convert]::ToBase64String($bytes)
$v=Assert-PaytmEncryptedKey (FixtureKey -Public $script:blob -Rounds 64) $script:blob
if(-not $v.encrypted){throw 'Custom encrypted identity failed'}
$denied=$false;try{Assert-PaytmEncryptedKey (FixtureKey -Public $script:blob)|Out-Null}catch{$denied=$true}
if(-not $denied){throw 'Default gateway identity weakened'}
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-clock-key-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$e=Join-Path $work 'evidence.json';[IO.File]::WriteAllText($e,'{}')
$src=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'NewPaytmClockReaderKey.ps1'))
$src=[regex]::Replace($src,'(?m)^\. \(Join-Path \$PSScriptRoot .*\)\r?\n','')
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$src=$src.Replace('ACFAE34FA921547D547BAAE3FEF1F156CA0AB85FBC71534D32D982E5AAD489BF',(Get-FileHash $e).Hash)
$src=$src.Replace("[Environment]::GetFolderPath('LocalApplicationData')",("'"+$work.Replace("'","''")+"'"))
function New-PaytmClockKeyMaterial($Path){
 $cipher=if($script:case -eq 'plaintext'){'none'}else{'aes256-ctr'}
 [IO.File]::WriteAllBytes($Path,(FixtureKey -Public $script:blob -Rounds 64 -Cipher $cipher))
 [IO.File]::WriteAllText(($Path+'.pub'),('ssh-ed25519 '+$script:blob+' marketbrain-clock-reader'))
 if($script:case -eq 'mismatch'){[IO.File]::WriteAllBytes($Path,(FixtureKey -Rounds 64))}
}
$count=2
foreach($script:case in @('pass','plaintext','mismatch')){
 $err=$null;$out=Join-Path $work $script:case
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$r=$raw|ConvertFrom-Json
 if($script:case -eq 'pass'){if($err -or -not $r.encrypted -or -not $r.directoryAclVerified){throw "Pass failed $err"}}
 elseif(-not $err -or $r.encrypted){throw 'Unsafe key accepted'}
 if($raw -match 'BEGIN OPENSSH' -or $r.vpsChanged -or $r.taskInstalled){throw 'Key leaked or authority added'}
 $count++
}
Write-Host "PASS: $count key parser/controller checks; real directory ACL setup, synthetic key bytes, no keygen or VPS calls."
