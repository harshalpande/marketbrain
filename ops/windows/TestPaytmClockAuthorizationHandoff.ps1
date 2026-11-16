#Requires -Version 7.0
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-clock-stage-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$e=Join-Path $work 'evidence.json';[IO.File]::WriteAllText($e,('{"fingerprint":"SHA256:TqoeCxI+3t+k2XTi8E6f+7iX4HCyhc1gshoZqnfyaX0","sourceHashes":{"reader":"'+('a'*64)+'"}}'))
$src=[IO.File]::ReadAllText((Join-Path $root 'AuthorizePaytmClockReaderKey.ps1'))
$src=$src.Replace('$PSScriptRoot',("'"+$root.Replace("'","''")+"'"))
$src=[regex]::Replace($src,"(?<=-cne ')[A-F0-9]{64}(?=')",(Get-FileHash $e).Hash)
$src=$src.Replace('$PSCommandPath',("'"+(Join-Path $root 'AuthorizePaytmClockReaderKey.ps1').Replace("'","''")+"'"))
function Set-Clipboard($Value){
 if($Value -notmatch "r = authorize_key\('[^']+', '([a-f0-9]{32})'\)"){throw 'Generated command'}
 $script:run=$Matches[1]
 if(-not $Value.StartsWith('sudo -n env SSH_CONNECTION=')){throw 'Wrong interpreter'}
}
function Read-Host {if($script:case -eq 'direct'){Get-Clipboard}else{'REPORT-COPIED'}}
function Get-Clipboard {
 $v=@{version=1;runId=$script:run;status='CLOCK_PUBLIC_KEY_AUTHORIZED_LOGIN_AND_CUSTODY_PENDING';failure=$null;keyInstalled=$true;passwordLocked=$true;effectivePolicyVerified=$true;readerVerified=$true;publicKeyReadable=$true;rollbackFailure=$null;sshReloaded=$false;privateKeyTransferred=$false;loginTested=$false;ordersEnabled=$false}
 if($script:case -eq 'failed'){$v.failure='CLOCK_STAGE_DENIAL';$v.effectivePolicyVerified=$false;$v.status='REVIEW_REQUIRED'}
 if($script:case -eq 'wrongrun'){$v.runId='0'*32}
 $s='MB_CLOCK_KEY_REPORT:'+ [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($v|ConvertTo-Json -Compress)))
 if($script:case -eq 'wrapped'){$s=$s.Insert(80,"`n    ")}
 return $s
}
foreach($script:case in @('pass','wrapped','direct','failed','wrongrun')){
 $err=$null;$out=Join-Path $work $script:case
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $r=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw|ConvertFrom-Json
 if($script:case -in @('pass','wrapped','direct')){if($err -or $r.status -cne 'CLOCK_PUBLIC_KEY_AUTHORIZED_LOGIN_AND_CUSTODY_PENDING'){throw "Pass failed $err"}}
 elseif(-not $err -or -not $r.failure){throw 'Invalid report accepted'}
}
Write-Host 'PASS: 5 public-key authorization handoff fixtures; no VPS calls.'
