#Requires -Version 5.1
# Imported after the shared key parser and native-process helpers. No actions on import.
function Get-HealthKeyContract {
 [pscustomobject]@{root='C:\ProgramData\MarketBrainPaytmHealth\key-custody';sid='S-1-5-21-3041730714-102984520-3202743044-1011';accountRun='4f60b36179694f8c9d54aae847bd8e05';blob='AAAAC3NzaC1lZDI1NTE5AAAAIB/0obZcN+dR0yxN6IWDvIsk37mxi6VbQfmlacUR/jk4';fingerprint='SHA256:TqoeCxI+3t+k2XTi8E6f+7iX4HCyhc1gshoZqnfyaX0'}
}
function Assert-HealthKeyIdentity {
 $id=Get-PaytmCustodyIdentity
 if($id.sid -cne (Get-HealthKeyContract).sid -or -not $id.nonAdmin){throw 'HEALTH_KEY_IDENTITY'}
}
function Assert-HealthKeyAgent {
 $r=Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')
 $pattern='^256 '+[regex]::Escape((Get-HealthKeyContract).fingerprint)+' [^\r\n]* \(ED25519\)$'
 if($r.StoppedByRunner -or $r.ExitCode -ne 0 -or $r.Stderr.Trim() -or $r.Stdout.Trim() -cnotmatch $pattern){throw 'HEALTH_KEY_AGENT_IDENTITY'}
}
function Invoke-HealthKeySequence($Report,[scriptblock]$Checkpoint){
 $c=Get-HealthKeyContract;$pub=Join-Path $c.root 'clock.pub';$key=Join-Path $c.root 'clock.openssh'
 Assert-HealthKeyIdentity;$Report.identityVerified=$true
 $v=Test-PaytmEncryptedKeyFile $key $c.blob
 if(-not $v.encrypted){throw 'HEALTH_KEY_ENCRYPTION'}
 Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Empty
 $Report.stage='IMPORT';$Report.importAttempted=$true;&$Checkpoint
 Write-Host 'CLOCK KEY WINDOW: enter the clock SSH-key passphrase. Not the Windows account password.'
 Invoke-PaytmInteractiveKeyImport $key
 Assert-HealthKeyAgent
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $true
 $Report.imported=$true;$Report.stage='TARGETED_REVOCATION';&$Checkpoint
 $r=Invoke-PaytmCustodyNative 'ssh-add.exe' @('-d',$pub)
 if($r.StoppedByRunner -or $r.ExitCode -ne 0){throw 'HEALTH_KEY_REVOCATION_FAILED'}
 Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Empty
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $false
 $Report.revocationVerified=$true;$Report.stage='REIMPORT';&$Checkpoint
 Write-Host 'CLOCK KEY WINDOW: enter the SAME clock SSH-key passphrase again.'
 Invoke-PaytmInteractiveKeyImport $key
 Assert-HealthKeyAgent
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',$pub)) $true
 $Report.reloadVerified=$true;$Report.stage='COMPLETE';&$Checkpoint
}
function New-HealthKeyWindowInfo([Security.SecureString]$Password){
 $source="&([scriptblock]::Create([IO.File]::ReadAllText('C:\ProgramData\MarketBrainPaytmHealth\key-custody\worker.ps1')))"
 $i=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('-NoLogo -NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))))
 if($i.FileName.Length+$i.Arguments.Length+4 -gt 1024){throw 'HEALTH_KEY_COMMAND_TOO_LONG'}
 $i.UseShellExecute=$false;$i.CreateNoWindow=$false;$i.LoadUserProfile=$true
 $i.UserName='marketbrain-health';$i.Domain=$env:COMPUTERNAME;$i.Password=$Password;$i.WorkingDirectory=(Get-HealthKeyContract).root
 foreach($n in @('SSH_AUTH_SOCK','SSH_AGENT_PID','SSH_ASKPASS','SSH_ASKPASS_REQUIRE','DISPLAY')){$i.EnvironmentVariables.Remove($n)}
 return $i
}
function New-HealthKeyFreshSource([string]$Run){
 if($Run -cnotmatch '^[a-f0-9]{32}$'){throw 'HEALTH_KEY_RUN'}
 $s=@'
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\key-custody'
foreach($n in @('parser.ps1','native.ps1','health.ps1')){. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\'+$n)))}
$r=[ordered]@{runId='__RUN__';identityVerified=$false;signingVerified=$false;failure=$null}
try{
 Assert-HealthKeyIdentity;$r.identityVerified=$true
 if([IO.File]::Exists($root+'\clock.openssh')){throw 'STAGED_KEY_PRESENT'}
 Assert-HealthKeyAgent
 Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',($root+'\clock.pub'))) $true
 $r.signingVerified=$true
}catch{$r.failure='HEALTH_KEY_FRESH_PROCESS_FAILED'}
$r|ConvertTo-Json -Compress
'@
 $s.Replace('__RUN__',$Run)
}
