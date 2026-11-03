#Requires -Version 5.1
[CmdletBinding()]param([switch]$AsObject)
$ErrorActionPreference='Stop'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1'))))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-bootstrap-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$count=0;$cases=0;$handles=[Collections.Generic.List[object]]::new()
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "BOOTSTRAP_TEST_$Name"};$script:count++}
$runnerSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1'))
try {
    $dll=Join-Path $temp 'native.dll';Add-Type -Path (Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs') -OutputAssembly $dll
    $transportDll=Join-Path $temp 'transport.dll';Add-Type -Path (Join-Path $PSScriptRoot 'PaytmTransportNative.cs') -OutputAssembly $transportDll
    foreach($kind in @('RestrictedSuccess','FileLoaderRegression','SourceDrift','HelperFailure','NativeFailure','DuplicateLease','ManagedPolicy','SigningFailure','TransportStop','TransportSourceDrift','TransportHelperFailure')){
        $cases++;$root=Join-Path $temp $kind;$null=New-Item -ItemType Directory -Path $root
        $work=Join-Path $root 'work';$null=New-Item -ItemType Directory -Path $work
        $source=$runnerSource.Replace('C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1',$root).Replace('C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1',$work).Replace('C:\ProgramData\MarketBrainPaytmGateway\key-custody',$root)
        # Isolated fixture only: substitute identity/session checks for this local child.
        # Deployed runner has no test switch and still requires the real SID, non-admin and session 0.
        $source=$source.Replace('S-1-5-21-3041730714-102984520-3202743044-1010',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $source=$source.Replace('([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)','$false')
        $source=$source.Replace('(Get-Process -Id $PID).SessionId -ne 0','$false')
        if($kind -ceq 'FileLoaderRegression'){$source=$source.Replace(". ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path `$root 'host.ps1'))))",". (Join-Path `$root 'host.ps1')")}
        $helper=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1'))
        if($kind -ceq 'HelperFailure'){$helper="throw 'SECRET_SHOULD_NOT_LEAK'"}
        if($kind -ceq 'SigningFailure'){$helper+="`nfunction Test-PaytmHostSigning {throw 'HOST_SIGNING_FAILED'}`n"}
        [IO.File]::WriteAllText((Join-Path $root 'host.ps1'),$helper)
        [IO.File]::WriteAllText((Join-Path $root 'runner.ps1'),$source)
        Copy-Item -LiteralPath $dll -Destination (Join-Path $root 'native.dll')
        if($kind -ceq 'NativeFailure'){[IO.File]::WriteAllText((Join-Path $root 'native.dll'),'invalid assembly')}
        $hashes=@{};foreach($n in @('host.ps1','runner.ps1','native.dll')){$hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash}
        if($kind -ceq 'SourceDrift'){$hashes['host.ps1']='0'*64}
        $id='a'*32
        $manifest=@{version=1;installationId=$id;hashes=$hashes}
        if($kind -like 'Transport*'){
            $manifest.transportVersion=1
            Copy-Item -LiteralPath $transportDll -Destination (Join-Path $root 'transport.dll')
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1') -Destination (Join-Path $root 'transport.ps1')
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmGatewaySupervisor.ps1') -Destination (Join-Path $root 'gateway.ps1')
            if($kind -ceq 'TransportHelperFailure'){[IO.File]::WriteAllText((Join-Path $root 'transport.ps1'),"throw 'SECRET_SHOULD_NOT_LEAK'")}
            foreach($n in @('transport.dll','transport.ps1','gateway.ps1')){$hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash}
            if($kind -ceq 'TransportSourceDrift'){$hashes['transport.ps1']='0'*64}
        }
        $manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'manifest.json')
        @{version=1;installationId=$id;mode=if($kind -ceq 'SigningFailure'){'LOCKED'}else{'STOP'}}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'control.json')
        $code="&([scriptblock]::Create([IO.File]::ReadAllText('"+(Join-Path $root 'runner.ps1')+"')))"
        if($kind -ceq 'ManagedPolicy'){$code="function Get-ExecutionPolicy { [pscustomobject]@{Scope='MachinePolicy';ExecutionPolicy='Restricted'} };"+$code}
        $lease=$null
        try {
            if($kind -ceq 'DuplicateLease'){$lease=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
            $h=Start-TunnelProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-NonInteractive','-ExecutionPolicy','Restricted','-EncodedCommand',$encoded)
            $handles.Add($h);$result=Complete-TunnelProcess $h 15
            Check (-not $result.StoppedByRunner) ($kind+'_BOUNDED_EXIT')
            $failure=Join-Path $work 'startup-failure.json';$status=Join-Path $work 'status.json'
            if($kind -cin @('RestrictedSuccess','TransportStop')){
                $s=[IO.File]::ReadAllText($status)|ConvertFrom-Json
                Check ($result.ExitCode -eq 0 -and $s.phase -ceq 'STOPPED' -and $s.jobContained -and -not $s.networkContacted -and -not $s.signingVerified) 'RESTRICTED_INLINE_SUCCESS'
                Check (-not (Test-Path -LiteralPath $failure)) 'NO_FALSE_FAILURE'
            }elseif($kind -ceq 'DuplicateLease'){
                Check ($result.ExitCode -eq 73 -and -not (Test-Path -LiteralPath $failure) -and -not (Test-Path -LiteralPath $status)) 'DUPLICATE_NO_OVERWRITE'
            }else{
                Check ($result.ExitCode -eq 1 -and (Test-Path -LiteralPath $failure)) ($kind+'_FAILURE_RECORDED')
                $text=[IO.File]::ReadAllText($failure);$f=$text|ConvertFrom-Json
                $expected=switch($kind){FileLoaderRegression{'LOAD_HELPER'} SourceDrift{'VERIFY_SOURCES'} HelperFailure{'LOAD_HELPER'} NativeFailure{'LOAD_NATIVE'} ManagedPolicy{'EXECUTION_POLICY'} SigningFailure{'OBSERVATION_LOOP'} TransportSourceDrift{'VERIFY_SOURCES'} TransportHelperFailure{'LOAD_TRANSPORT'}}
                Check ($f.stage -ceq $expected -and $f.details.type -and $text.Length -lt 4096 -and $text -notmatch 'SECRET_SHOULD_NOT_LEAK' -and -not $f.networkContacted) ($kind+'_SAFE_DIAGNOSTICS')
                if($kind -ceq 'FileLoaderRegression'){Check ($f.details.outerType -ceq 'PSSecurityException') 'ORIGINAL_LOADER_DEFECT_REPRODUCED'}
                if($kind -ceq 'SigningFailure'){
                    $s=[IO.File]::ReadAllText($status)|ConvertFrom-Json
                    Check ($s.phase -ceq 'BLOCKED' -and $s.failure -ceq 'HOST_SIGNING_FAILED') 'SIGNING_BLOCK_PRESERVED'
                }
            }
        }finally{if($lease){$lease.Dispose()}}
    }
    $summary=[pscustomobject]@{status='BOOTSTRAP_ENGINEERING_PASSED';assertions=$count;childProcessCases=$cases;
        persistentExecutionPolicyChanged=$false;fixtureIdentitySubstitution=$true;actualScheduledAccountTested=$false;networkContacted=$false}
    if($AsObject){$summary}else{$summary|ConvertTo-Json}
}finally{
    foreach($h in $handles){if($null -eq $h.Result){try{$null=Complete-TunnelProcess $h -StopNow}catch{}}}
    # All fixture children have exited; delete only the verified unique temporary fixture root.
    $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'mb-bootstrap-*'){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
