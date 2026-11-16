#Requires -Version 7.0
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmGatewayAccount.ps1"
. "$PSScriptRoot/PaytmHealthAccount.ps1"
$sid='S-1-5-21-1-2-3-1001';$run='a'*32
$info=New-PaytmAccountProbeStartInfo $null 'marketbrain-health'
if($info.UserName -cne 'marketbrain-health' -or $info.WorkingDirectory -cne 'C:\ProgramData\MarketBrainPaytmHealth' -or -not $info.RedirectStandardInput -or -not $info.CreateNoWindow){throw 'HEALTH_PROBE_LAUNCH'}
Assert-PaytmAccountProbeCommandLine $info
$source=New-PaytmAccountProbeSource $sid $run 'C:\ProgramData\MarketBrainPaytmHealth'
if($source.Contains('MarketBrainPaytmGateway') -or -not $source.Contains('MarketBrainPaytmHealth') -or -not $source.Contains($sid)){throw 'HEALTH_PROBE_SOURCE'}
$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors){throw $errors}
$default=New-PaytmAccountProbeStartInfo $null
if($default.UserName -cne 'marketbrain-gateway' -or -not (New-PaytmAccountProbeSource $sid $run).Contains('MarketBrainPaytmGateway')){throw 'GATEWAY_DEFAULT_CHANGED'}
$count=3
foreach($case in @('apply','collision','probeFailure','verify','groupFailure')){
 & {
  param($case)
  $script:healthMutations=0;$script:healthEnabled=$false;$script:healthRead=0
  function Get-LocalUser {param($Name,$SID) if($SID){return [pscustomobject]@{Enabled=$true}};if($case -ceq 'collision'){[pscustomobject]@{Name='marketbrain-health'}}}
  function Test-Path {return $false}
  function New-LocalUser {param($Name,$Password,$Description,[switch]$Disabled,$ErrorAction)
   if($Name -cne 'marketbrain-health' -or -not $Disabled){throw 'UNEXPECTED_CREATE'}
   $script:healthMutations++;[pscustomobject]@{SID=[pscustomobject]@{Value=$sid}}
  }
  function Get-LocalGroupMember {param($SID) @()}
  function Add-LocalGroupMember {param($SID,$Member,$ErrorAction) if($SID -cne 'S-1-5-32-545'){throw 'WRONG_GROUP'};$script:healthMutations++}
  function New-Item {param($ItemType,$Path,$ErrorAction) if(-not $Path.StartsWith('C:\ProgramData\MarketBrainPaytmHealth')){throw 'WRONG_PATH'};$script:healthMutations++}
  function Set-PaytmAccountDirectoryAcl {param($Path,$AccountSid,[switch]$Writable) if($AccountSid -cne $sid){throw 'WRONG_ACL_SID'}}
  function Write-PaytmAccountNewJson {param($Path,$Value) if($Value.sid -cne $sid -or $Value.containsPrivateKey){throw 'WRONG_MANIFEST'}}
  function Read-PaytmHealthAccount {$script:healthRead++;if($case -ceq 'groupFailure'){throw 'HEALTH_ACCOUNT_GROUP_MEMBERSHIP'};[pscustomobject]@{sid=$sid}}
  function Enable-LocalUser {param($SID,$ErrorAction) $script:healthEnabled=$true;$script:healthMutations++}
  function Invoke-PaytmAccountProbeProcess {param($Info,$Source,$Diagnostics)
   if($Info.UserName -cne 'marketbrain-health' -or $Source.Contains('MarketBrainPaytmGateway')){throw 'WRONG_PROBE_BINDING'}
   [pscustomobject]@{version=1;runId=$run;failure=$null;agentExit=1;sidMatched=$true;nonAdmin=$true;protectedWriteDenied=$true;workWriteReadDelete=$true;agentEmpty=($case -cne 'probeFailure')}
  }
  $r=[ordered]@{stage='';status='REVIEW_REQUIRED';accountSid=$null;createdAccount=$false;createdDirectory=$false;probe=$null;probeLaunch=@{}}
  $caught=$false;try{Invoke-PaytmHealthAccountSetup $r $null $run {} -VerifyOnly:($case -ceq 'verify')}catch{$caught=$true}
  if($case -cin @('apply','verify')){
   if($caught -or $r.status -cne 'HEALTH_ACCOUNT_AND_STORAGE_VERIFIED_KEY_CUSTODY_PENDING'){throw "FAILED_$case"}
  }elseif(-not $caught -or $r.status -cne 'REVIEW_REQUIRED'){throw "NOT_REJECTED_$case"}
  if($case -cin @('collision','verify') -and $script:healthMutations -ne 0){throw 'UNEXPECTED_MUTATION'}
  if($case -ceq 'groupFailure' -and $script:healthEnabled){throw 'ENABLED_BEFORE_GROUP_CHECK'}
  if($case -ceq 'probeFailure' -and (-not $r.createdAccount -or -not $r.createdDirectory -or $null -eq $r.probe)){throw 'PARTIAL_EVIDENCE_LOST'}
 } $case
 $count++
}
Write-Host "$count health account checks passed; no real accounts, services, keys or VPS changes."
