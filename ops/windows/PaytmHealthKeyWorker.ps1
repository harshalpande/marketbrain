#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\key-custody'
foreach($n in @('parser.ps1','native.ps1','health.ps1')){. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\'+$n)))}
$plan=[IO.File]::ReadAllText($root+'\plan.json')|ConvertFrom-Json
if($plan.runId -cnotmatch '^[a-f0-9]{32}$' -or $plan.sid -cne (Get-HealthKeyContract).sid){throw 'HEALTH_KEY_PLAN'}
$path='C:\ProgramData\MarketBrainPaytmHealth\work\key-custody-'+$plan.runId+'.json'
$r=[ordered]@{version=1;runId=$plan.runId;stage='IDENTITY';identityVerified=$false;importAttempted=$false;imported=$false;revocationVerified=$false;reloadVerified=$false;failure=$null;nativeError=$null}
$f=$null
function Save-HealthWorker {
 $b=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Compress));$f.Position=0;$f.SetLength(0);$f.Write($b,0,$b.Length);$f.Flush($true)
}
try{
 $Host.UI.RawUI.WindowTitle='MarketBrain CLOCK KEY - enter SSH passphrase twice'
 $f=[IO.File]::Open($path,'CreateNew','Write','Read');Save-HealthWorker
 Invoke-HealthKeySequence $r {Save-HealthWorker}
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(HEALTH_KEY|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_KEY_WORKER_FAILED'};$e=$_.Exception.GetBaseException()
 if($e -is [ComponentModel.Win32Exception]){$r.nativeError=$e.NativeErrorCode}
}finally{if($null -ne $f){try{Save-HealthWorker}finally{$f.Dispose()}}}
if($r.failure){exit 1}else{exit 0}
