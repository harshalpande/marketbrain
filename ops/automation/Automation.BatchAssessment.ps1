#requires -Version 7.2
function Get-AutomationBatchAssessment($Job) {
    try {
    $findings=[Collections.Generic.List[string]]::new()
    if($Job.state -ne 'SUCCEEDED'){return @{collectionPassed=$false;transportPassed=$false;findings=@('JOB_NOT_SUCCEEDED')}}
    $p=$Job.result.paytmObservation
    $transport=$p.loopbackTcpConnected -eq $true
    $probes=@($p.proxyObservations)
    if($probes.Count -ne 2){$transport=$false}
    foreach($probe in $probes){
        if($probe.observation.exitCode -ne 0 -or $probe.observation.timedOut -ne $false -or $probe.observation.stdout -notmatch '^\d{3}\|200\|127\.0\.0\.1\|'){$transport=$false}
    }
    if(-not $transport){$findings.Add('TRANSPORT_FAILED')}
    if($p.elevated -ne $true){$findings.Add('RUNNER_NOT_ELEVATED')}
    if($p.windowsStatus.exitCode -ne 0 -or $p.windowsSource.exitCode -ne 0){$findings.Add('WINDOWS_TIME_QUERY_FAILED')}
    $syncError=$null
    if($p.windowsStatus.stdout -match 'Last Sync Error:\s*(\d+)'){$syncError=[int]$Matches[1]}
    if($null -eq $syncError -or $syncError -ne 0){$findings.Add('WINDOWS_SYNC_NOT_CONFIRMED')}
    $s=$p.gatewaySupervisor.files.'status.json'
    if($s.state -ne 'READ'){$findings.Add('SUPERVISOR_STATUS_UNAVAILABLE')}
    elseif($s.fields.phase -ne 'TRANSPORT_READY'){$findings.Add('SUPERVISOR_NOT_READY')}
    if($Job.result.ordersEnabled -ne $false){$findings.Add('SCOPE_UNCONFIRMED')}
    return @{collectionPassed=$true;transportPassed=$transport;elevated=$p.elevated;windowsSyncError=$syncError;findings=@($findings);applicationHealthAccepted=$false;brokerReadinessAccepted=$false}
    } catch {
        return @{collectionPassed=$false;transportPassed=$false;findings=@('MALFORMED_DIAGNOSTIC');applicationHealthAccepted=$false;brokerReadinessAccepted=$false}
    }
}
