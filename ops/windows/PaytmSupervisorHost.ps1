#Requires -Version 5.1
# Definitions shared by the installed PS5 host and PS7 controller. No side effects on import.
function Read-PaytmHostJson([string]$Path,[int]$Maximum=16384) {
    # Delete sharing lets the writer atomically replace a heartbeat while it is being read.
    # The opened handle retains the old complete snapshot. Never read an unbounded stream.
    $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($stream.Length -gt $Maximum){throw 'HOST_FILE_MISSING_OR_LARGE'}
        $reader=[IO.StreamReader]::new($stream)
        try{
            $buffer=[char[]]::new($Maximum+1);$length=$reader.ReadBlock($buffer,0,$buffer.Length)
            if($length -gt $Maximum){throw 'HOST_FILE_MISSING_OR_LARGE'}
            ([string]::new($buffer,0,$length)) | ConvertFrom-Json -ErrorAction Stop
        }finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Write-PaytmHostJson([string]$Path,$Value) {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 8 -Compress))
    if($bytes.Length -gt 16384){throw 'HOST_REPORT_TOO_LARGE'}
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $stream=[IO.File]::Open($temporary,'CreateNew','Write','None')
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    try{
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Assert-PaytmHostControl($Control,[string]$InstallationId) {
    # No enable mode exists in this release. A future transport release needs separate acceptance.
    if($Control.version -ne 1 -or $Control.installationId -cne $InstallationId -or $Control.mode -cnotin @('LOCKED','STOP')){throw 'HOST_CONTROL_INVALID'}
}
function Assert-PaytmHostStatus($Value,[string]$InstallationId,[ValidateSet('LOCKED','STOPPED')][string]$Phase='LOCKED') {
    if($Value.version -ne 1 -or $Value.installationId -cne $InstallationId -or $Value.phase -cne $Phase -or $null -ne $Value.failure){throw 'HOST_STATUS_NOT_ACCEPTED'}
    if($Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.sequence -lt 1 -or $Value.processId -le 0 -or $Value.sessionId -ne 0 -or $Value.elapsedSeconds -lt 0){throw 'HOST_STATUS_IDENTITY_INVALID'}
    foreach($field in @('identityVerified','jobContained')){
        if($Value.$field -isnot [bool] -or -not $Value.$field){throw 'HOST_STATUS_PROOF_MISSING'}
    }
    foreach($field in @('agentIdentityVerified','signingVerified','privateCopyAbsent')){
        if($Value.$field -isnot [bool] -or ($Phase -ceq 'LOCKED' -and -not $Value.$field)){throw 'HOST_STATUS_PROOF_MISSING'}
    }
    foreach($field in @('networkContacted','transportEnabled','brokerReady','ordersEnabled')){
        if($Value.$field -isnot [bool] -or $Value.$field){throw 'HOST_STATUS_SCOPE_INVALID'}
    }
}
function Assert-PaytmHostAdvance($First,$Second) {
    if($First.instanceId -cne $Second.instanceId -or $First.processId -ne $Second.processId -or $Second.sequence -le $First.sequence -or $Second.elapsedSeconds -lt $First.elapsedSeconds){throw 'HOST_HEARTBEAT_NOT_ADVANCING'}
}
function Test-PaytmHostSigning([string]$CustodyRoot) {
    if([IO.File]::Exists((Join-Path $CustodyRoot 'gateway.openssh'))){throw 'HOST_PRIVATE_STAGING_PRESENT'}
    $tool='C:\Windows\System32\OpenSSH\ssh-add.exe'
    $identity=[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@('-l'),10000)
    if($identity.TimedOut -or $identity.ExitCode -ne 0){throw 'HOST_AGENT_UNAVAILABLE'}
    $lines=@($identity.Output.Trim() -split '\r?\n'|Where-Object {$_.Trim()})
    if($lines.Count -ne 1 -or $lines[0] -cnotmatch '^256 SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI .+ \(ED25519\)$'){throw 'HOST_AGENT_IDENTITY_DRIFT'}
    $signed=[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@('-T',(Join-Path $CustodyRoot 'gateway.pub')),10000)
    if($signed.TimedOut -or $signed.ExitCode -ne 0){throw 'HOST_SIGNING_FAILED'}
}
function Invoke-PaytmHostObservationLoop([string]$Root,[string]$Work,[string]$Custody,$Report,$Clock) {
    $control=Read-PaytmHostJson (Join-Path $Root 'control.json');Assert-PaytmHostControl $control $Report.installationId
    if($control.mode -ceq 'LOCKED'){
        if([IO.File]::Exists((Join-Path $Work 'blocked.json'))){throw 'HOST_PREVIOUS_FAILURE_REVIEW_REQUIRED'}
        Test-PaytmHostSigning $Custody
        $Report.agentIdentityVerified=$true;$Report.signingVerified=$true;$Report.privateCopyAbsent=$true
    }
    while($true){
        $control=Read-PaytmHostJson (Join-Path $Root 'control.json');Assert-PaytmHostControl $control $Report.installationId
        $Report.phase=if($control.mode -ceq 'STOP'){'STOPPED'}else{'LOCKED'}
        $Report.sequence++;$Report.elapsedSeconds=[math]::Round($Clock.Elapsed.TotalSeconds,3);$Report.observedUtc=[DateTime]::UtcNow.ToString('o')
        Write-PaytmHostJson (Join-Path $Work 'status.json') $Report
        if($control.mode -ceq 'STOP'){return}
        Start-Sleep -Seconds 2
    }
}
