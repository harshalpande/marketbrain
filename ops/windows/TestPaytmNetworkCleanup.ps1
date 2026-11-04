#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1'))))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-network-cleanup-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$handles=[Collections.Generic.List[object]]::new();$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "NETWORK_CLEANUP_TEST_$Name"};$script:checks++}
try{
 foreach($case in @('release','deadline','relaunch','foreign','lease')){
  $run=[guid]::NewGuid().ToString('N');$root=Join-Path $temp ('network-'+$run);$null=New-Item -ItemType Directory -Path $root
  $name='MarketBrain-Network-Test-'+$run
  $owned=@{Name=$name;Group='MarketBrain bounded network test';Description=$(if($case -eq 'foreign'){'different'}else{$run})}
  if($case -eq 'foreign'){Check ($owned.Description -eq 'different') 'FOREIGN_FIXTURE'}
  @($owned,@{Name='unrelated';Group='other';Description='other'})|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'rules.json')
  if($case -eq 'relaunch'){[IO.File]::WriteAllText((Join-Path $root 'started'),'old')}
  $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RunPaytmNetworkCleanup.ps1'))
  # Isolated copy only: production has no identity bypass and uses real NetSecurity.
  $source=$source.Replace("if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18')",'if($false)')
  $source=$source.Replace('Import-Module NetSecurity -ErrorAction Stop','# isolated NetSecurity boundaries')
  $source=$source.Replace('C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\network-',(Join-Path $temp 'network-'))
  $prefix=@'
function Get-NetFirewallRule {$items=Get-Content -Raw -LiteralPath (Join-Path $root 'rules.json')|ConvertFrom-Json;foreach($item in $items){$item}}
function Remove-NetFirewallRule {param($InputObject); @(Get-NetFirewallRule|Where-Object Name -CNE $InputObject.Name)|ConvertTo-Json -AsArray:$false|Set-Content -LiteralPath (Join-Path $root 'rules.json')}
'@
  # PS5 has no ConvertTo-Json -AsArray; use an explicit array pipeline object.
  $prefix=$prefix.Replace('@(Get-NetFirewallRule|Where-Object Name -CNE $InputObject.Name)|ConvertTo-Json -AsArray:$false','ConvertTo-Json -InputObject @(Get-NetFirewallRule|Where-Object Name -CNE $InputObject.Name)')
  $encodedSource=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
  $code=$prefix+"`n& ([scriptblock]::Create([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('"+$encodedSource+"')))) -RunId '"+$run+"' -WindowSeconds 5"
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  $h=Start-TunnelProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);$handles.Add($h)
  $lease=$null
  try{
   if($case -eq 'lease'){$lease=[IO.File]::Open((Join-Path $root 'rule.lock'),'OpenOrCreate','ReadWrite','None')}
   if($case -in @('release','lease','foreign')){
    $clock=[Diagnostics.Stopwatch]::StartNew();$ready=$false
    do{if(Test-Path -LiteralPath (Join-Path $root 'cleanup.json')){$v=Get-Content -Raw -LiteralPath (Join-Path $root 'cleanup.json')|ConvertFrom-Json;$ready=$v.phase -eq 'READY';if($ready){break}};Start-Sleep -Milliseconds 100}while($clock.Elapsed.TotalSeconds -lt 15)
    Check $ready 'WORKER_READY'
    [IO.File]::WriteAllText((Join-Path $root 'release'),'release')
    if($lease){Start-Sleep -Seconds 1;$items=Get-Content -Raw -LiteralPath (Join-Path $root 'rules.json')|ConvertFrom-Json;Check (@($items|Where-Object Name -CEQ $name).Count -eq 1) 'LEASE_PREVENTS_CLEANUP_RACE';$lease.Dispose();$lease=$null}
   }
   $result=Complete-TunnelProcess $h 20
   $v=Get-Content -Raw -LiteralPath (Join-Path $root 'cleanup.json')|ConvertFrom-Json
   $rows=Get-Content -Raw -LiteralPath (Join-Path $root 'rules.json')|ConvertFrom-Json
   Check (-not $result.StoppedByRunner) 'BOUNDED_CHILD'
   if($case -eq 'foreign'){
    Check ($result.ExitCode -eq 1 -and $v.phase -eq 'FAILED' -and $rows.Count -eq 2) 'FOREIGN_RULE_PRESERVED'
   }
   else{Check ($result.ExitCode -eq 0 -and $v.ruleRemoved -and $v.phase -eq 'REMOVED' -and $rows.Count -eq 1 -and $rows[0].Name -eq 'unrelated') 'ONLY_OWN_RULE_REMOVED'}
  }finally{if($lease){$lease.Dispose()}}
 }
 [pscustomobject]@{status='NETWORK_CLEANUP_WORKER_PASSED';assertions=$checks;nativePs5Cases=5;actualTimerAndFileLease=$true;firewallAndIdentitySubstituted=$true}|ConvertTo-Json
}finally{
 foreach($h in $handles){if($null -eq $h.Result){$null=Complete-TunnelProcess $h -StopNow}}
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-network-cleanup-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
