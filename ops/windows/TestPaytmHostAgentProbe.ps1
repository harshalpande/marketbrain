#Requires -Version 5.1
$ErrorActionPreference='Stop'
foreach($name in @('PaytmSupervisorHost.ps1','PaytmGatewayFailureEvidence.ps1')){
 . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))))
}
Add-Type @'
namespace MarketBrain.Supervisor {
 public class ProbeFixtureResult {
  public int ExitCode; public bool TimedOut; public string Output="", Error="";
  public long StartMilliseconds=3,WaitMilliseconds=10,StopMilliseconds=0,DrainMilliseconds=1,TotalMilliseconds=14;
 }
 public static class NativeCommand {
  public static ProbeFixtureResult Result; public static bool Fail;
  public static ProbeFixtureResult Run(string tool,string[] args,int timeout) {
   if(timeout!=10000 || !tool.EndsWith("ssh-add.exe"))throw new System.Exception("WRONG_CALL");
   if(Fail)throw new System.ComponentModel.Win32Exception(5,"PRIVATE_ERROR");
   return Result;
  }
 }
}
'@
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw $Name};$script:checks++}
foreach($case in @('ok','empty','connection','timeout','unknown','exception')){
 $r=[MarketBrain.Supervisor.ProbeFixtureResult]::new();$r.Output='PRIVATE_KEY_DESCRIPTION';$r.Error='PRIVATE_STDERR'
 switch($case){
  empty {$r.ExitCode=1;$r.Output='The agent has no identities.'}
  connection {$r.ExitCode=2;$r.Error='Error connecting to agent: PRIVATE_MESSAGE'}
  timeout {$r.ExitCode=-1;$r.TimedOut=$true}
  unknown {$r.ExitCode=7}
 }
 [MarketBrain.Supervisor.NativeCommand]::Result=$r;[MarketBrain.Supervisor.NativeCommand]::Fail=($case -eq 'exception')
 $failed=$false;try{$null=Invoke-PaytmHostAgentProbe @('-l') LIST_IDENTITIES}catch{$failed=$true}
 Check ($failed -eq ($case -eq 'exception')) ($case+'_EXCEPTION')
 $expected=@{ok='COMMAND_SUCCEEDED';empty='NO_IDENTITIES';connection='AGENT_CONNECTION_ERROR';timeout='TIMEOUT';unknown='UNCLASSIFIED';exception='UNCLASSIFIED'}[$case]
 Check ($paytmLastAgentProbe.classification -ceq $expected) ($case+'_CLASSIFICATION')
 $v=ConvertTo-PaytmWorkerEvidence @{agentProbe=$paytmLastAgentProbe}
 Check (($v|ConvertTo-Json -Depth 8) -notmatch 'PRIVATE') ($case+'_NO_RAW_TEXT')
 Check ($v.agentProbe.operation -ceq 'LIST_IDENTITIES' -and $v.agentProbe.elapsedMilliseconds -ge 0) ($case+'_OPERATION_AND_TIME')
 if($case -ne 'exception'){Check ($v.agentProbe.TotalMilliseconds -eq 14 -and $v.agentProbe.StartMilliseconds -eq 3) ($case+'_NATIVE_PHASES')}
 else{Check ($v.agentProbe.nativeErrorCode -eq 5) 'WIN32_CODE_RETAINED'}
}
Write-Host "PASS: $checks agent probe assertions; native calls mocked."
