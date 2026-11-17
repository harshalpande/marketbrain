#Requires -Version 5.1
# Template, installed under protected storage with bound run and output paths.
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\key-custody'
foreach($n in @('parser.ps1','native.ps1','health.ps1')){. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\'+$n)))}
$r=[ordered]@{version=1;runId='__RUN__';stage='IDENTITY';processId=$PID;sessionId=$null;identityVerified=$false;nonAdmin=$false;nonInteractiveSession=$false;privateCopyAbsent=$false;agentIdentityVerified=$false;signingChecks=0;clockVerified=$false;clockResult=$null;failure=$null;elapsedSeconds=0;keyImported=$false;networkContacted=$false;ordersEnabled=$false}
$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 Assert-HealthKeyIdentity;$r.identityVerified=$true;$r.nonAdmin=$true
 $r.sessionId=(Get-Process -Id $PID).SessionId
 if($r.sessionId -ne 0){throw 'SCHEDULE_INTERACTIVE_SESSION'};$r.nonInteractiveSession=$true
 if([IO.File]::Exists($root+'\clock.openssh')){throw 'SCHEDULE_PRIVATE_STAGING_PRESENT'};$r.privateCopyAbsent=$true
 Assert-HealthKeyAgent;$r.agentIdentityVerified=$true
 $r.stage='SIGNING'
 foreach($attempt in 1..2){Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',($root+'\clock.pub'))) $true;$r.signingChecks++}
 $r.stage='CLOCK';$nonce=[guid]::NewGuid().ToString('N')
 $a=@('-F','none','-T','-4','-i',($root+'\clock.pub'))
 foreach($o in @('BatchMode=yes','IdentitiesOnly=yes','StrictHostKeyChecking=yes','GlobalKnownHostsFile=none','UserKnownHostsFile="__KNOWN__"','HostKeyAlgorithms=rsa-sha2-512,rsa-sha2-256','UpdateHostKeys=no','VerifyHostKeyDNS=no','PasswordAuthentication=no','KbdInteractiveAuthentication=no','PreferredAuthentications=publickey','NumberOfPasswordPrompts=0','AddKeysToAgent=no','ConnectTimeout=15','ConnectionAttempts=1','ServerAliveInterval=5','ServerAliveCountMax=2','ClearAllForwardings=yes','ProxyCommand=none','ProxyJump=none','PermitLocalCommand=no')){$a+=@('-o',$o)}
 $a+=@('marketbrain-health@130.250.191.137',('marketbrain-clock '+$nonce))
 $r.networkContacted=$true
 $result=Invoke-PaytmCustodyNative 'ssh.exe' $a 25
 $r.clockResult=@{nonce=$nonce;exitCode=$result.ExitCode;timedOut=$result.StoppedByRunner;stdout=$result.Stdout;stderr=$result.Stderr}
 if($result.StoppedByRunner -or $result.ExitCode -ne 0 -or $result.Stdout.Trim() -cnotmatch ('^MB_CLOCK_V1\|'+$nonce+'\|[0-9]{13}\|yes$')){throw 'SCHEDULE_CLOCK_NOT_VERIFIED'}
 $r.clockVerified=$true;$r.stage='COMPLETE'
}catch{$r.failure=if($_.Exception.Message -cmatch '^(SCHEDULE|HEALTH_KEY|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_WORKER_FAILED'}}finally{
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 $bytes=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 5 -Compress))
 $f=[IO.File]::Open('__RESULT__','CreateNew','Write','Read');try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
}
if($r.failure){exit 1}else{exit 0}
