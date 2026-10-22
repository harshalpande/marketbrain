# Definitions only. Read-only service diagnostics; no remote requests or repairs.
. (Join-Path $PSScriptRoot 'PaytmOperationsFollowUp.ps1')
function Assert-PaytmTimeAccessEvidence([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 100000){throw 'OPS_TIME_ACCESS_PRIOR_INVALID'}
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if($hash -cne 'F176A5F08BD3C57C6289CBDB09C867E2CBEB023805D4CDC919DCFFD0BF636701'){throw 'OPS_TIME_ACCESS_PRIOR_HASH_MISMATCH'}
    [pscustomobject]@{runId='11fea1e34d3a41e6b3dc10893178311c';sha256=$hash}
}
function Get-PaytmTimeAccessCommandSpecs {
    $sc=Join-Path $env:WINDIR 'System32\sc.exe'
    $tm=Join-Path $env:WINDIR 'System32\w32tm.exe'
    @(
        @{label='Service status';executable=$sc;arguments=@('queryex','W32Time')}
        @{label='Service configuration';executable=$sc;arguments=@('qc','W32Time')}
        @{label='Service security descriptor';executable=$sc;arguments=@('sdshow','W32Time')}
        @{label='Service triggers';executable=$sc;arguments=@('qtriggerinfo','W32Time')}
        @{label='Time configuration';executable=$tm;arguments=@('/query','/configuration','/verbose')}
        @{label='Time status';executable=$tm;arguments=@('/query','/status','/verbose')}
        @{label='Time policy';executable=(Join-Path $env:WINDIR 'System32\reg.exe');arguments=@('query','HKLM\SOFTWARE\Policies\Microsoft\W32Time','/s')}
    )
}
function Read-PaytmTimeAccessProbe([string]$Text) {
    if($Text.Length -gt 12000){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
    try{$probe=$Text|ConvertFrom-Json -ErrorAction Stop}catch{throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
    if($probe.schemaVersion -ne 1 -or $probe.target -cne 'LOCAL_W32Time' -or $probe.administratorEnabled -isnot [bool] -or $probe.serviceStartInvoked -isnot [bool] -or $probe.serviceStartInvoked -or $probe.securityChanged -isnot [bool] -or $probe.securityChanged){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
    $expected=[ordered]@{QUERY_CONFIG=1;QUERY_STATUS=4;READ_CONTROL=131072;SERVICE_START=16}
    if(@($probe.rights).Count -ne 4){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
    foreach($name in $expected.Keys){
        $rows=@($probe.rights|Where-Object right -CEQ $name)
        if($rows.Count -ne 1){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
        $row=$rows[0]
        if($row.mask -ne $expected[$name] -or $row.allowed -isnot [bool] -or $row.stage -cnotin @('OpenSCManager','OpenService') -or $row.win32Error -isnot [long] -and $row.win32Error -isnot [int]){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
        if($row.win32Error -lt 0 -or ($row.allowed -and ($row.win32Error -ne 0 -or $row.stage -cne 'OpenService')) -or (-not $row.allowed -and $row.win32Error -eq 0)){throw 'OPS_TIME_ACCESS_PROBE_INVALID'}
    }
    return $probe
}
function Invoke-PaytmTimeAccessInspection {
    $result=[ordered]@{administratorEnabled=(Test-PaytmOperationsAdministrator);commands=@();probe=$null;probeFailure=$null;findings=@();clockAccuracyProven=$false;serviceStartInvoked=$false;securityChanged=$false}
    if(-not $result.administratorEnabled){throw 'OPS_ADMIN_POWERSHELL_REQUIRED'}
    $specs=@(Get-PaytmTimeAccessCommandSpecs)
    for($i=0;$i -lt $specs.Count;$i++){
        $percent=10+[int](65*$i/$specs.Count)
        Write-Progress -Activity 'Windows Time access diagnosis' -Status $specs[$i].label -PercentComplete $percent
        Write-Host "[$percent%] Read-only: $($specs[$i].label)"
        $result.commands+=Invoke-PaytmTimeCommand $specs[$i].label $specs[$i].executable $specs[$i].arguments
    }
    Write-Host '[80%] Checking local service access rights WITHOUT starting the service (30-second child deadline).'
    try{
        $child=Invoke-PaperRuntimeProcess (Join-Path $PSHOME 'pwsh.exe') @('-NoLogo','-NoProfile','-File',(Join-Path $PSScriptRoot 'ReadPaytmTimeAccessProbe.ps1')) $PSScriptRoot 30
        $result.probeElapsedSeconds=$child.elapsedSeconds
        if($child.exitCode -ne 0){throw 'OPS_TIME_ACCESS_PROBE_PROCESS_FAILED'}
        $result.probe=Read-PaytmTimeAccessProbe $child.stdout
        if(-not $result.probe.administratorEnabled){$result.findings+='CHILD_ADMINISTRATOR_NOT_ENABLED'}
        $start=@($result.probe.rights|Where-Object right -CEQ 'SERVICE_START')[0]
        if($start.allowed){$result.findings+='START_HANDLE_ALLOWED_NOT_START_OR_SYNC_PROOF'}
        elseif($start.win32Error -eq 5){$result.findings+='START_HANDLE_ACCESS_DENIED'}
        else{$result.findings+='START_HANDLE_OTHER_ERROR'}
    }catch{
        $result.probeFailure=if($_.Exception.Message -cmatch '^(OPS_TIME_ACCESS_[A-Z_]+|RUNTIME_PROCESS_TIMEOUT)$'){$_.Exception.Message}else{'OPS_TIME_ACCESS_PROBE_FAILED'}
        $result.findings+='ACCESS_PROBE_INCOMPLETE'
    }
    foreach($command in $result.commands){
        if($command.failure -or $null -eq $command.exitCode -or $command.exitCode -ne 0){$result.findings+='QUERY_NOT_SUCCESSFUL: '+$command.label}
    }
    # Stopped W32Time can make w32tm queries fail; absent policy can return reg exit 1.
    # Preserve these observations, never infer corruption or reset ACLs from them.
    [pscustomobject]$result
}
