#Requires -Version 7.0
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmGatewayKeyCustody.ps1"
. "$PSScriptRoot/PaytmHealthKeyCustody.ps1"
$c=Get-HealthKeyContract;$count=0
foreach($case in @('success','wrongIdentity','admin','plaintext','existingAgent','importFailure','signFailure','revokeFailure','reloadFailure')){
 & {
  param($case)
  $script:healthLoaded=($case -ceq 'existingAgent');$script:imports=0;$script:revokes=0
  function Get-PaytmCustodyIdentity {[pscustomobject]@{sid=if($case -ceq 'wrongIdentity'){'wrong'}else{$c.sid};nonAdmin=($case -cne 'admin')}}
  function Test-PaytmEncryptedKeyFile {param($Path,$ExpectedPublicBlob) if($ExpectedPublicBlob -cne $c.blob){throw 'WRONG_KEY'};[pscustomobject]@{encrypted=($case -cne 'plaintext')}}
  function Invoke-PaytmInteractiveKeyImport {param($Path)
   $script:imports++
   if($case -ceq 'importFailure' -or ($case -ceq 'reloadFailure' -and $script:imports -eq 2)){throw 'KEY_IMPORT_FAILED'}
   $script:healthLoaded=$true
  }
  function Invoke-PaytmCustodyNative {param($Tool,[string[]]$Arguments,$Seconds)
   if($Tool -cne 'ssh-add.exe'){throw 'UNEXPECTED_TOOL'}
   $exit=0;$out='';$err=''
   switch($Arguments[0]){
    '-l' {if($script:healthLoaded){$out='256 '+$c.fingerprint+' clock (ED25519)'}else{$exit=1;$out='The agent has no identities.'}}
    '-T' {if(-not $script:healthLoaded -or $case -ceq 'signFailure'){$exit=1}}
    '-d' {if($Arguments[1] -cne (Join-Path $c.root 'clock.pub')){throw 'UNSCOPED_REMOVAL'};$script:revokes++;if($case -ceq 'revokeFailure'){$exit=1}else{$script:healthLoaded=$false}}
    default {throw 'UNEXPECTED_OPERATION'}
   }
   [pscustomobject]@{ExitCode=$exit;Stdout=$out;Stderr=$err;StoppedByRunner=$false}
  }
  $r=[ordered]@{identityVerified=$false;stage='';importAttempted=$false;imported=$false;revocationVerified=$false;reloadVerified=$false}
  $caught=$false;try{Invoke-HealthKeySequence $r {}}catch{$caught=$true}
  if($case -ceq 'success'){
   if($caught -or $r.stage -cne 'COMPLETE' -or -not $r.reloadVerified -or $script:imports -ne 2 -or $script:revokes -ne 1){throw 'SUCCESS_FAILED'}
  }elseif(-not $caught -or $r.stage -ceq 'COMPLETE'){throw "FAILURE_ACCEPTED_$case"}
  if($case -cin @('wrongIdentity','admin','plaintext','existingAgent') -and $script:imports -ne 0){throw 'PRECHECK_IMPORTED_KEY'}
  if($case -ceq 'reloadFailure' -and (-not $r.revocationVerified -or $r.reloadVerified)){throw 'PARTIAL_STATE_LOST'}
 } $case
 $count++
}
$i=New-HealthKeyWindowInfo $null
if($i.UserName -cne 'marketbrain-health' -or $i.CreateNoWindow -or $i.WorkingDirectory -cne $c.root -or ($i.FileName.Length+$i.Arguments.Length+4) -gt 1024){throw 'WINDOW_CONTRACT'};$count++
$source=New-HealthKeyFreshSource ('a'*32)
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e -or $source.Contains('MarketBrainPaytmGateway') -or -not $source.Contains('STAGED_KEY_PRESENT')){throw 'FRESH_SOURCE'};$count++
foreach($n in @('PaytmHealthKeyWorker.ps1','InstallPaytmHealthKeyCustody.ps1')){
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $n),[ref]$t,[ref]$e)
 if($e){throw $e};$count++
}
Write-Host "$count health custody checks passed. No actual imports, accounts, agent changes or network connections."
