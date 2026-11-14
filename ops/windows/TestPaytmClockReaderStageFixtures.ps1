#Requires -Version 7.0
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-clock-stage-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$e=Join-Path $work 'evidence.json';[IO.File]::WriteAllText($e,'{}')
$src=[IO.File]::ReadAllText((Join-Path $root 'StagePaytmClockReader.ps1'))
$src=$src.Replace('$PSScriptRoot',("'"+$root.Replace("'","''")+"'"))
$src=[regex]::Replace($src,"(?<=-cne ')[A-F0-9]{64}(?=')",(Get-FileHash $e).Hash)
$src=$src.Replace('$PSCommandPath',("'"+(Join-Path $root 'StagePaytmClockReader.ps1').Replace("'","''")+"'"))
function Set-Clipboard($Value){
 if($Value -notmatch "r = stage\('[^']+', '[^']+', '([a-f0-9]{32})'\)"){throw 'Generated command'}
 $script:run=$Matches[1]
 if(-not $Value.StartsWith('sudo -n /usr/bin/python3 -I -')){throw 'Wrong interpreter'}
}
function Read-Host {'REPORT-COPIED'}
function Get-Clipboard {
 $v=@{version=1;runId=$script:run;status='CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING';failure=$null;accountCreated=$true;passwordLocked=$true;programVerified=$true;allowedCommandVerified=$true;deniedCommandVerified=$true;keylessVerified=$true;sshConfigurationChanged=$false;sshAccessEnabled=$false;ordersEnabled=$false}
 if($script:case -eq 'failed'){$v.failure='CLOCK_STAGE_DENIAL';$v.deniedCommandVerified=$false;$v.status='REVIEW_REQUIRED'}
 if($script:case -eq 'wrongrun'){$v.runId='0'*32}
 $s='MB_CLOCK_STAGE_REPORT:'+ [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($v|ConvertTo-Json -Compress)))
 if($script:case -eq 'wrapped'){$s=$s.Insert(80,"`n    ")}
 return $s
}
foreach($script:case in @('pass','wrapped','failed','wrongrun')){
 $err=$null;$out=Join-Path $work $script:case
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $r=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw|ConvertFrom-Json
 if($script:case -in @('pass','wrapped')){if($err -or $r.status -cne 'CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING'){throw "Pass failed $err"}}
 elseif(-not $err -or -not $r.failure){throw 'Invalid report accepted'}
}
Write-Host 'PASS: 4 staging handoff fixtures; no VPS calls.'
