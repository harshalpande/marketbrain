# Definitions only. Selective inspection, never docker inspect's full secret-bearing output.
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
function Get-PaperPortAssessment($Snapshot,[string]$ContainerPort,[string]$HostPort) {
    $findings=[Collections.Generic.List[string]]::new()
    if($Snapshot.running -isnot [bool] -or -not $Snapshot.running){$findings.Add('CONTAINER_NOT_RUNNING')}
    if([string]::IsNullOrWhiteSpace($Snapshot.networkMode) -or $Snapshot.networkMode -in @('host','none') -or $Snapshot.networkMode.StartsWith('container:')){$findings.Add('NETWORK_MODE_NEEDS_REVIEW')}
    $bindings=[Collections.Generic.List[object]]::new();$expected=$false
    foreach($property in $Snapshot.ports.PSObject.Properties){
        foreach($binding in @($property.Value)){
            if($null -eq $binding){continue}
            $bindings.Add([ordered]@{containerPort=$property.Name;hostIp=$binding.HostIp;hostPort=$binding.HostPort})
            if($binding.HostIp -notin @('127.0.0.1','::1')){$findings.Add('NON_LOOPBACK_PUBLISHED_PORT')}
            if($property.Name -ceq $ContainerPort -and $binding.HostPort -ceq $HostPort){$expected=$true}
            else{$findings.Add('UNEXPECTED_PUBLISHED_PORT')}
        }
    }
    if(-not $expected){$findings.Add('EXPECTED_PORT_NOT_PUBLISHED')}
    return [pscustomobject]@{bindings=$bindings.ToArray();findings=$findings.ToArray();loopbackBindingsObserved=($findings.Count -eq 0)}
}
function Get-PaperWriterPrivateBoundary {
    if($PSVersionTable.PSVersion.Major -lt 7){throw 'BOUNDARY_POWERSHELL_7_REQUIRED'}
    $docker=Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1 -ExpandProperty Source
    if(-not $docker){throw 'BOUNDARY_DOCKER_MISSING'}
    $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $steps=[Collections.Generic.List[object]]::new();$containers=[Collections.Generic.List[object]]::new();$findings=[Collections.Generic.List[string]]::new()
    function Invoke-BoundaryDocker([string[]]$Arguments,[string]$Stage) {
        $result=Invoke-PaperCatalogProcess $docker $Arguments $root 15
        $steps.Add([ordered]@{stage=$Stage;exitCode=$result.exitCode;timedOut=$result.timedOut;elapsedSeconds=$result.elapsedSeconds})
        if($result.timedOut -or $result.exitCode -ne 0 -or $result.stdout.Length -gt 65536){throw 'BOUNDARY_DOCKER_CHECK_FAILED'}
        return $result.stdout.Trim()
    }
    $route='NOT_INSPECTED';$listeners=@();$failureCode=$null
    try {
        foreach($service in @('marketbrain-service','marketbrain-ui')){
            $ids=Invoke-BoundaryDocker @('ps','--filter',"label=com.docker.compose.service=$service",'--format','{{.ID}}') ('LOCATE_'+$service)
            if($ids -cnotmatch '^[a-f0-9]{12,64}$'){throw 'BOUNDARY_CONTAINER_MISSING_OR_AMBIGUOUS'}
            $format='{"running":{{json .State.Running}},"networkMode":{{json .HostConfig.NetworkMode}},"ports":{{json .NetworkSettings.Ports}}}'
            $snapshot=(Invoke-BoundaryDocker @('inspect','--format',$format,$ids) ('PORTS_'+$service))|ConvertFrom-Json
            $containerPort=if($service -ceq 'marketbrain-service'){'8080/tcp'}else{'80/tcp'}
            $hostPort=if($service -ceq 'marketbrain-service'){'8080'}else{'8081'}
            $assessment=Get-PaperPortAssessment $snapshot $containerPort $hostPort
            $containers.Add([ordered]@{service=$service;id=$ids;networkMode=$snapshot.networkMode;assessment=$assessment})
            foreach($finding in $assessment.findings){$findings.Add($service+':'+$finding)}
            if($service -ceq 'marketbrain-service'){
                # Return a fixed classification only; never print the URL, username or password.
                $classification='case "$MARKETBRAIN_DB_URL" in jdbc:postgresql://host.docker.internal:5432/marketbrain) printf SAME_MACHINE_HOST_ALIAS ;; jdbc:postgresql://127.0.0.1:5432/marketbrain|jdbc:postgresql://localhost:5432/marketbrain) printf CONTAINER_LOOPBACK_NEEDS_REVIEW ;; *) printf UNRECOGNIZED_ROUTE ;; esac'
                $observedRoute=Invoke-BoundaryDocker @('exec',$ids,'/bin/sh','-c',$classification) 'CLASSIFY_CONFIGURED_ROUTE'
                if($observedRoute -cnotin @('SAME_MACHINE_HOST_ALIAS','CONTAINER_LOOPBACK_NEEDS_REVIEW','UNRECOGNIZED_ROUTE')){throw 'BOUNDARY_ROUTE_RESPONSE_INVALID'}
                $route=$observedRoute
                if($route -cne 'SAME_MACHINE_HOST_ALIAS'){$findings.Add('CONFIGURED_DATABASE_ROUTE_NEEDS_REVIEW')}
            }
        }
        # Host-side metadata, no connection to PostgreSQL and no change to firewall/listeners.
        $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 5432 -ErrorAction Stop|Select-Object LocalAddress,LocalPort)
        if($listeners.Count -eq 0){$findings.Add('DATABASE_LISTENER_NOT_OBSERVED')}
        if(@($listeners|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -gt 0){$findings.Add('DATABASE_NON_LOOPBACK_LISTENER_REQUIRES_HBA_FIREWALL_REVIEW')}
    }
    catch {$failureCode='BOUNDARY_COLLECTION_FAILED';if($_.Exception.Message -cmatch '^BOUNDARY_[A-Z0-9_]+$'){$failureCode=$_.Exception.Message};$findings.Add($failureCode)}
    return [ordered]@{status=if($failureCode){'INCOMPLETE'}else{'OBSERVATIONS_CAPTURED_REVIEW_REQUIRED'};failureCode=$failureCode;containers=$containers.ToArray();configuredDatabaseRoute=$route;databaseListeners=$listeners;steps=$steps.ToArray();findings=$findings.ToArray();actualDatabaseSessionProven=$false;firewallVerified=$false;externalReachabilityTested=$false;activationAuthorized=$false}
}
