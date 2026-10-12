#Requires -Version 7.0
# Child process: bounded by the parent; emits one fixed-shape JSON, never raw CIM errors.
$ErrorActionPreference='Stop'
function Test-PortRelevant($Filter) {
    if([string]$Filter.Protocol -notin @('TCP','6','Any','256')){return $false}
    foreach($port in @($Filter.LocalPort)){
        if([string]$port -eq 'Any'){return $true}
        if([string]$port -match '^\d+$'){if([int]$port -eq 5432){return $true};continue}
        if([string]$port -match '^(\d+)-(\d+)$'){if([int]$Matches[1] -le 5432 -and [int]$Matches[2] -ge 5432){return $true};continue}
        return $true # Dynamic/unknown selector must not be silently excluded.
    }
    return $false
}
$report=[ordered]@{version='PAPER_FIREWALL_SNAPSHOT_V2';status='RUNNING';profiles=@();rules=@();inboundRuleCount=0;scannedRuleCount=0;candidateRuleCount=0;truncated=$true;failureCode=$null;elapsedSeconds=0;limits=@{inboundRules=2000;candidateRules=1000;payloadBytes=1048576;softSeconds=180};effectiveAccessProven=$false;configurationChanged=$false}
$watch=[Diagnostics.Stopwatch]::StartNew()
$rows=[Collections.Generic.List[object]]::new();$seen=@{};$rowBytes=0
function Assert-Deadline {if($watch.Elapsed.TotalSeconds -ge 180){throw 'FIREWALL_TIME_LIMIT'}}
function Write-Snapshot {
    $report.rules=$rows.ToArray();$report.candidateRuleCount=$rows.Count;$report.elapsedSeconds=$watch.Elapsed.TotalSeconds
    $report|ConvertTo-Json -Depth 8 -Compress
}
try {
    $report.profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore |Select-Object Name,Enabled,DefaultInboundAction,AllowInboundRules,AllowLocalFirewallRules)
    Write-Snapshot
    # Filter at the provider first. Do not enumerate outbound/disabled filters or guess filter identity joins.
    $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound|Select-Object -First 2001)
    $report.inboundRuleCount=$rules.Count
    if($rules.Count -gt 2000){throw 'FIREWALL_INBOUND_RULE_LIMIT'}
    foreach($rule in $rules){
        Assert-Deadline
        if([string]$rule.Enabled -ne 'True' -or [string]$rule.Direction -ne 'Inbound' -or -not $rule.Name -or $seen.ContainsKey($rule.Name)){throw 'FIREWALL_RULE_IDENTITY_INVALID'}
        $seen[$rule.Name]=$true
        $filters=@(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule)
        if($filters.Count -ne 1){throw 'FIREWALL_FILTER_CARDINALITY_INVALID'}
        $filter=$filters[0]
        if(Test-PortRelevant $filter){
            if($rows.Count -ge 1000){throw 'FIREWALL_RULE_LIMIT'}
            Assert-Deadline
            $addresses=@(Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule)
            Assert-Deadline
            $applications=@(Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule)
            Assert-Deadline
            $services=@(Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule)
            if($addresses.Count -ne 1 -or $applications.Count -ne 1 -or $services.Count -ne 1){throw 'FIREWALL_FILTER_CARDINALITY_INVALID'}
            $address=$addresses[0];$application=$applications[0];$service=$services[0]
            $row=[ordered]@{name=$rule.Name;action=[string]$rule.Action;profile=[string]$rule.Profile;protocol=[string]$filter.Protocol;localPort=@($filter.LocalPort);remotePort=@($filter.RemotePort);localAddress=@($address.LocalAddress);remoteAddress=@($address.RemoteAddress);program=$application.Program;service=$service.Service;edgeTraversal=[string]$rule.EdgeTraversalPolicy;policySourceType=[string]$rule.PolicyStoreSourceType}
            $bytes=[Text.Encoding]::UTF8.GetByteCount(($row|ConvertTo-Json -Depth 5 -Compress))+1
            if($rowBytes+$bytes -gt 1000000){throw 'FIREWALL_PAYLOAD_LIMIT'}
            $rowBytes+=$bytes;$rows.Add($row)
        }
        $report.scannedRuleCount++
        # JSON lines, not extra files: parent retains the last complete checkpoint on hard timeout.
        if($report.scannedRuleCount%100 -eq 0){Write-Snapshot}
    }
    Assert-Deadline
    $report.truncated=$false;$report.status='METADATA_CAPTURED_REVIEW_REQUIRED'
}catch{$report.failureCode='FIREWALL_QUERY_FAILED';if($_.Exception.Message -cmatch '^FIREWALL_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}}
if($report.status -cne 'METADATA_CAPTURED_REVIEW_REQUIRED'){$report.status='FAILED'}
Write-Snapshot
if($report.status -ceq 'FAILED'){exit 2}
