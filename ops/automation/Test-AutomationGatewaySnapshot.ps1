#requires -Version 7.2
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')
$directory=Join-Path $env:TEMP ('mb-gateway-snapshot-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
try {
    $path=Join-Path $directory 'fixture.json'
    $fixture=@{version=1;installationId=('a'*32);phase='BLOCKED';failure='HOST_AGENT_UNAVAILABLE';processId=123;ordersEnabled=$false;password='NEVER_RETURN';privateKey='NEVER_RETURN';details=@{type='Win32Exception';nativeErrorCode=5;stderr='NEVER_RETURN'};transportState=@{phase='STOPPED';reason='OWNER_STOP';token='NEVER_RETURN'};worker=@{signingChecks=2;nonAdmin=$true;password='NEVER_RETURN';nativeObservations=@(@{classification='NO_IDENTITIES';exitCode=1;stderr='NEVER_RETURN'})};sourceHashes=@{'worker.ps1'=('A'*64);'token'='NEVER_RETURN'}}
    [IO.File]::WriteAllText($path,($fixture|ConvertTo-Json -Depth 5))
    $before=(Get-FileHash $path).Hash
    $r=Read-AutomationGatewaySnapshot $path
    if ($r.state -ne 'READ' -or $r.fields.failure -ne 'HOST_AGENT_UNAVAILABLE' -or $r.fields.details.nativeErrorCode -ne 5 -or $r.fields.transportState.phase -ne 'STOPPED') { throw 'Relevant failure fields lost' }
    if (($r|ConvertTo-Json -Depth 6) -match 'NEVER_RETURN' -or (Get-FileHash $path).Hash -ne $before) { throw 'Secret exposed or file changed' }
    if($r.fields.worker.signingChecks -ne 2 -or $r.fields.sourceHashes.'worker.ps1' -ne ('A'*64)){throw 'Signing evidence dropped'}
    if($r.fields.worker.nativeObservations[0].classification -ne 'NO_IDENTITIES' -or $r.fields.worker.nativeObservations[0].exitCode -ne 1){throw 'Native failure classification lost'}
    [IO.File]::WriteAllText($path,('X'*65537))
    if ((Read-AutomationGatewaySnapshot $path).state -ne 'TOO_LARGE') { throw 'Size limit failed' }
    [IO.File]::WriteAllText($path,'not-json')
    if ((Read-AutomationGatewaySnapshot $path).state -ne 'UNAVAILABLE') { throw 'Malformed evidence accepted' }
    $missing=Read-AutomationGatewaySnapshot (Join-Path $directory 'absent.json')
    if ($missing.state -ne 'UNAVAILABLE' -or $missing.errorType -ne 'FileNotFoundException') { throw 'Missing evidence misclassified' }
    $call=0
    function Invoke-AutomationNativeObservation([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds) {
        if ($TimeoutSeconds -ne 12) { throw 'Task query unbounded' }
        $script:call++
        return @{exitCode=1;stdout='{}';timedOut=$false}
    }
    $gateway=Get-AutomationGatewayObservation
    if ($gateway.readOnly -ne $true -or $gateway.files.Count -ne 6 -or $script:call -ne 1) { throw 'Incomplete fixed supervisor capture' }
    Write-Host 'PASS: first failure retained, sensitive fields excluded, source unchanged, size/malformed/missing checks, six fixed snapshots and bounded task query.'
} finally {
    Remove-Item -LiteralPath (Join-Path $directory 'fixture.json') -ErrorAction SilentlyContinue
    [IO.Directory]::Delete($directory)
}
