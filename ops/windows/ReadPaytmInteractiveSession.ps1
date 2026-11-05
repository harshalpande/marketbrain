#Requires -Version 5.1
$ErrorActionPreference='Stop'
function Get-PaytmInteractiveSession {
 if(-not ('MarketBrain.SessionObservation' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
namespace MarketBrain {
 public static class SessionObservation {
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr data, int length, out int needed);
  public static string AuthenticationId() {
   using(var identity=WindowsIdentity.GetCurrent()) {
    int needed; GetTokenInformation(identity.Token,10,IntPtr.Zero,0,out needed);
    if(needed<16 || needed>4096) throw new InvalidOperationException("SESSION_TOKEN_SIZE");
    IntPtr buffer=Marshal.AllocHGlobal(needed);
    try {
     if(!GetTokenInformation(identity.Token,10,buffer,needed,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error());
     // TOKEN_STATISTICS begins with TokenId then AuthenticationId (two 8-byte LUIDs).
     return unchecked((uint)Marshal.ReadInt32(buffer,12)).ToString("X8")+unchecked((uint)Marshal.ReadInt32(buffer,8)).ToString("X8");
    } finally { Marshal.FreeHGlobal(buffer); }
   }
  }
 }
}
'@
 }
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$sha=[Security.Cryptography.SHA256]::Create()
 try{
  $sidHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity.User.Value))).Replace('-','')
 }finally{$identity.Dispose();$sha.Dispose()}
 $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
 if($session -le 0){throw 'SESSION_INTERACTIVE_CONTROLLER_REQUIRED'}
 [pscustomobject]@{userSidHash=$sidHash;sessionId=$session;authenticationId=[MarketBrain.SessionObservation]::AuthenticationId()}
}

Get-PaytmInteractiveSession | ConvertTo-Json -Compress
