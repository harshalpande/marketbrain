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
$report=[ordered]@{version='PAPER_FIREWALL_SNAPSHOT_V1';status='FAILED';profiles=@();rules=@();filterCount=0;truncated=$false;failureCode=$null;effectiveAccessProven=$false;configurationChanged=$false}
try {
    $report.profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore |Select-Object Name,Enabled,DefaultInboundAction,AllowInboundRules,AllowLocalFirewallRules)
    $filters=@(Get-NetFirewallPortFilter -PolicyStore ActiveStore|Select-Object -First 2001)
    $report.filterCount=$filters.Count
    if($filters.Count -gt 2000){$report.truncated=$true;throw 'FIREWALL_FILTER_LIMIT'}
    $rows=[Collections.Generic.List[object]]::new();$seen=@{}
    foreach($filter in $filters){
        if(-not (Test-PortRelevant $filter)){continue}
        foreach($rule in @(Get-NetFirewallRule -AssociatedNetFirewallPortFilter $filter |Where-Object {([string]$_.Enabled -eq 'True') -and ([string]$_.Direction -eq 'Inbound')})){
            if($seen.ContainsKey($rule.Name)){continue};$seen[$rule.Name]=$true
            if($rows.Count -ge 100){$report.truncated=$true;throw 'FIREWALL_RULE_LIMIT'}
            $address=Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule
            $application=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule
            $service=Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule
            $rows.Add([ordered]@{name=$rule.Name;action=[string]$rule.Action;profile=[string]$rule.Profile;protocol=[string]$filter.Protocol;localPort=@($filter.LocalPort);remotePort=@($filter.RemotePort);localAddress=@($address.LocalAddress);remoteAddress=@($address.RemoteAddress);program=$application.Program;service=$service.Service;edgeTraversal=[string]$rule.EdgeTraversalPolicy;policySourceType=[string]$rule.PolicyStoreSourceType})
        }
    }
    $report.rules=$rows.ToArray();$report.status='METADATA_CAPTURED_REVIEW_REQUIRED'
}catch{$report.failureCode='FIREWALL_QUERY_FAILED';if($_.Exception.Message -cmatch '^FIREWALL_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}}
$report|ConvertTo-Json -Depth 8 -Compress
if($report.status -ceq 'FAILED'){exit 2}
