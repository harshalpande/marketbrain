#Requires -Version 5.1
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs'))
$fixture=@'
namespace MarketBrain.Supervisor {
 public static class NativeProcessFixture {
  sealed class Fake : NativeCommand.ICommandProcess {
   internal string Mode; internal bool Exited; internal int Kills,Waits;
   internal Fake(string mode) {Mode=mode;}
   public bool Start(){if(Mode=="start")throw new System.ComponentModel.Win32Exception(5);return true;}
   public void CloseInput(){if(Mode=="primary")throw new System.ComponentModel.Win32Exception(2);}
   public System.Threading.Tasks.Task<string> Output(){
    if(Mode=="drain") {var t=new System.Threading.Tasks.TaskCompletionSource<string>();t.SetException(new System.IO.IOException("PRIVATE_DATA"));return t.Task;}
    return System.Threading.Tasks.Task.FromResult("result");
   }
   public System.Threading.Tasks.Task<string> Error(){return System.Threading.Tasks.Task.FromResult("");}
   public bool Wait(int ms){
    Waits++;
    if(Mode=="wait" && Waits==1)throw new System.ComponentModel.Win32Exception(5);
    if(Mode=="live" || Mode=="primary")return false;
    if((Mode=="timeout" || Mode=="race" || Mode=="raceinvalid") && Waits==1)return false;
    Exited=true;return true;
   }
   public void Kill(){
    Kills++;
    if(Mode=="race" || Mode=="raceinvalid")Exited=true;
    if(Mode=="raceinvalid")throw new System.InvalidOperationException();
    if(Mode=="race" || Mode=="live" || Mode=="primary")throw new System.ComponentModel.Win32Exception(5);
    Exited=true;
   }
   public bool HasExited {get{if(Mode=="cleanup")throw new System.ComponentModel.Win32Exception(5);return Exited;}}
   public int ExitCode {get{return 0;}}
  }
  public static int Test(){
   int count=0;
   foreach(string mode in new string[]{"normal","start","wait","timeout","race","raceinvalid","live","primary","cleanup","drain"}){
    var f=new Fake(mode);System.Exception error=null;BoundedResult r=null;
    try{r=NativeCommand.RunCore(f,1);}catch(System.Exception e){error=e.GetBaseException();}
    bool pass=false;
    if(mode=="normal")pass=error==null && r.Output=="result" && !r.TimedOut && f.Kills==0;
    if(mode=="timeout" || mode=="race" || mode=="raceinvalid")pass=error==null && r.TimedOut && f.Exited && f.Kills==1;
    string operation=error==null?null:(string)error.Data["MarketBrainOperation"];
    var w=error as System.ComponentModel.Win32Exception;
    if(mode=="start")pass=w!=null && w.NativeErrorCode==5 && operation=="START" && f.Kills==0;
    if(mode=="wait")pass=w!=null && operation=="WAIT" && f.Exited;
    if(mode=="live")pass=w!=null && operation=="TIMEOUT_STOP" && !f.Exited;
    if(mode=="primary")pass=w!=null && w.NativeErrorCode==2 && operation=="CLOSE_INPUT" && (int)error.Data["MarketBrainCleanupCode"]==5;
    if(mode=="cleanup")pass=w!=null && operation=="CLEANUP_CHECK";
    if(mode=="drain")pass=error is System.IO.IOException && operation=="DRAIN";
    if(!pass)throw new System.Exception("NATIVE_FIXTURE_"+mode);count++;
   }
   return count;
  }
 }
}
'@
Add-Type -TypeDefinition ($source+"`n"+$fixture)
$count=[MarketBrain.Supervisor.NativeProcessFixture]::Test()
$r=[MarketBrain.Supervisor.NativeCommand]::Run('C:\Windows\System32\curl.exe',[string[]]@('--version'),5000)
if($r.ExitCode -ne 0 -or $r.TimedOut -or -not $r.Output.StartsWith('curl')){throw 'NATIVE_ACTUAL_CURL_FAILED'};$count++
$code='Start-Sleep -Seconds 20'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$r=[MarketBrain.Supervisor.NativeCommand]::Run('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',[string[]]@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded),100)
if(-not $r.TimedOut){throw 'NATIVE_ACTUAL_TIMEOUT_FAILED'};$count++
[pscustomobject]@{status='NATIVE_PROCESS_PASSED';assertions=$count;syntheticScenarios=10;actualCurlVersion=$true;actualChildTimeout=$true;externalNetwork=$false}|ConvertTo-Json
