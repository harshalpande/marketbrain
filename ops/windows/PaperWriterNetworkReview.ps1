# Read-only definitions. This is targeted metadata collection, not a firewall simulator.
function Get-PaperNetworkTargetNames {
    return @('{974B68F8-3C84-465F-A460-844587E9EB43}', '{AD00E124-1653-417F-B894-E01EA777B23E}')
}
function Get-PaperNetworkField($Object, [string]$Name) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
function Get-PaperNetworkAddressLinks($Rules, $Addresses, $Adapters, $Profiles) {
    $links = [Collections.Generic.List[object]]::new()
    foreach ($rule in $Rules) {
        foreach ($address in @($rule.filters.address.LocalAddress)) {
            $ip = $null
            if (-not [Net.IPAddress]::TryParse([string]$address, [ref]$ip)) {
                $links.Add([ordered]@{ruleName=$rule.name;selector=$address;status='NON_LITERAL_SELECTOR_REQUIRES_REVIEW';matches=@()})
                continue
            }
            $matches = [Collections.Generic.List[object]]::new()
            foreach ($entry in $Addresses) {
                $candidate = $null
                if ([Net.IPAddress]::TryParse([string]$entry.IPAddress, [ref]$candidate) -and $ip.Equals($candidate)) {
                    $matches.Add([ordered]@{address=$entry;adapters=@($Adapters | Where-Object { $_.ifIndex -eq $entry.InterfaceIndex });connectionProfiles=@($Profiles | Where-Object { $_.InterfaceIndex -eq $entry.InterfaceIndex })})
                }
            }
            $links.Add([ordered]@{ruleName=$rule.name;selector=$address;status=if($matches.Count){'ADDRESS_OBSERVED_ON_INTERFACE'}else{'ADDRESS_NOT_OBSERVED'};matches=$matches.ToArray()})
        }
    }
    return ,$links.ToArray()
}
function Invoke-PaperWriterNetworkCollection([scriptblock]$Checkpoint) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $r = [ordered]@{version='PAPER_WRITER_NETWORK_SNAPSHOT_V1';status='RUNNING';phase='START';rules=@();rulesAfter=@();missingRuleNames=@();ruleCount=0;enumeratedRuleCount=0;enumeratedRuleCountAfter=0;selectedRulesStableAtEnd=$false;addresses=@();adapters=@();connectionProfiles=@();firewallProfiles=@();listeners=@();listenerProcesses=@();addressLinks=@();queries=@();failureCode=$null;failureLine=$null;elapsedSeconds=0;configurationChanged=$false;databaseContacted=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false;effectiveAccessProven=$false;snapshotAtomic=$false}
    function Emit([string]$Phase) {
        $r.phase=$Phase; $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
        & $Checkpoint ([pscustomobject]$r)
    }
    function Query([string]$Label, [scriptblock]$Read) {
        if ($watch.Elapsed.TotalSeconds -gt 120) { throw 'NETWORK_SOFT_TIMEOUT' }
        $q=[Diagnostics.Stopwatch]::StartNew()
        try { & $Read } finally { $r.queries+=@{label=$Label;elapsedSeconds=$q.Elapsed.TotalSeconds} }
        if ($watch.Elapsed.TotalSeconds -gt 120) { throw 'NETWORK_SOFT_TIMEOUT' }
    }
    function Bounded($Values, [int]$Limit) {
        $items=@($Values | Where-Object { $null -ne $_ })
        if ($items.Count -gt $Limit) { throw 'NETWORK_COLLECTION_LIMIT' }
        return ,$items
    }
    function Rules {
        $all=Bounded (Query 'FIREWALL_RULE_IDENTITIES' { Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop | Select-Object -First 2001 }) 2000
        $rows=[Collections.Generic.List[object]]::new()
        foreach ($name in (Get-PaperNetworkTargetNames)) {
            $found=@($all | Where-Object { $_.Name -ieq $name })
            if ($found.Count -gt 1) { throw 'NETWORK_DUPLICATE_RULE_ID' }
            if (-not $found.Count) { continue }
            $rule=$found[0]
            $row=[ordered]@{name=$name;displayName=$rule.DisplayName;enabled=[string]$rule.Enabled;direction=[string]$rule.Direction;action=[string]$rule.Action;profile=[string]$rule.Profile;policySourceType=[string]$rule.PolicyStoreSourceType;edgeTraversal=[string]$rule.EdgeTraversalPolicy;filters=[ordered]@{};missingFields=@()}
            $specs=@(
                @('port','Get-NetFirewallPortFilter',@('Protocol','LocalPort','RemotePort','DynamicTarget')),
                @('address','Get-NetFirewallAddressFilter',@('LocalAddress','RemoteAddress')),
                @('application','Get-NetFirewallApplicationFilter',@('Program','Package')),
                @('service','Get-NetFirewallServiceFilter',@('Service')),
                @('interface','Get-NetFirewallInterfaceFilter',@('InterfaceAlias')),
                @('interfaceType','Get-NetFirewallInterfaceTypeFilter',@('InterfaceType')),
                @('security','Get-NetFirewallSecurityFilter',@('Authentication','Encryption','OverrideBlockRules','LocalUser','RemoteUser','RemoteMachine'))
            )
            foreach ($spec in $specs) {
                $command=$spec[1]
                $values=@(Query $command { & $command -AssociatedNetFirewallRule $rule -ErrorAction Stop })
                if ($values.Count -ne 1) { throw 'NETWORK_FILTER_CARDINALITY' }
                $selected=[ordered]@{}
                foreach ($field in $spec[2]) {
                    if ($null -eq $values[0].PSObject.Properties[$field]) { $row.missingFields+=($spec[0]+'.'+$field) }
                    $selected[$field]=Get-PaperNetworkField $values[0] $field
                }
                $row.filters[$spec[0]]=$selected
            }
            $rows.Add([pscustomobject]$row)
        }
        return [pscustomobject]@{count=$all.Count;rows=$rows.ToArray()}
    }
    try {
        Emit 'START'
        $first=Rules; $r.enumeratedRuleCount=$first.count; $r.rules=$first.rows; $r.ruleCount=$r.rules.Count
        $r.missingRuleNames=@(Get-PaperNetworkTargetNames | Where-Object { $_ -notin @($r.rules | ForEach-Object { $_.name }) })
        Emit 'SELECTED_RULES_CAPTURED'
        $r.addresses=Bounded (Query 'INTERFACE_ADDRESSES' { Get-NetIPAddress -ErrorAction Stop | Select-Object -First 257 -Property IPAddress,InterfaceIndex,InterfaceAlias,AddressFamily,AddressState,PrefixLength }) 256
        $r.adapters=Bounded (Query 'ADAPTER_IDENTITIES' { Get-NetAdapter -IncludeHidden -ErrorAction Stop | Select-Object -First 129 -Property ifIndex,Name,InterfaceDescription,Status }) 128
        $r.connectionProfiles=Bounded (Query 'CONNECTION_PROFILES' { Get-NetConnectionProfile -ErrorAction Stop | Select-Object -First 65 -Property InterfaceIndex,InterfaceAlias,NetworkCategory,IPv4Connectivity,IPv6Connectivity }) 64
        $r.firewallProfiles=Bounded (Query 'FIREWALL_PROFILES' { Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Select-Object -First 4 -Property Name,Enabled,DefaultInboundAction,DefaultOutboundAction,AllowInboundRules,AllowLocalFirewallRules,DisabledInterfaceAliases }) 3
        $listening=Bounded (Query 'LISTENING_PORT_METADATA' { Get-NetTCPConnection -State Listen -ErrorAction Stop | Select-Object -First 2049 -Property LocalAddress,LocalPort,OwningProcess }) 2048
        $r.listeners=@($listening | Where-Object { $_.LocalPort -eq 5432 })
        if ($r.listeners.Count -gt 16) { throw 'NETWORK_LISTENER_LIMIT' }
        foreach ($owner in @($r.listeners | Select-Object -ExpandProperty OwningProcess -Unique)) {
            if ([string]$owner -cnotmatch '^[0-9]{1,10}$') { throw 'NETWORK_PROCESS_ID_INVALID' }
            $process=@(Query 'LISTENER_PROCESS_IDENTITY' { Get-CimInstance Win32_Process -Filter ('ProcessId = '+$owner) -ErrorAction Stop | Select-Object -First 2 -Property ProcessId,Name,ExecutablePath })
            if ($process.Count -ne 1) { throw 'NETWORK_LISTENER_PROCESS_MISSING_OR_AMBIGUOUS' }
            $r.listenerProcesses+=@($process[0])
        }
        $r.addressLinks=Get-PaperNetworkAddressLinks $r.rules $r.addresses $r.adapters $r.connectionProfiles
        Emit 'NETWORK_MAPPING_CAPTURED'
        $last=Rules; $r.enumeratedRuleCountAfter=$last.count; $r.rulesAfter=$last.rows
        $r.selectedRulesStableAtEnd=(ConvertTo-Json -InputObject $r.rules -Depth 12 -Compress) -ceq (ConvertTo-Json -InputObject $r.rulesAfter -Depth 12 -Compress)
        # Missing/changed rules are findings, not a fabricated successful access verdict.
        $r.status='TARGETED_NETWORK_CAPTURED_REVIEW_REQUIRED'
        Emit 'COMPLETE'
    } catch {
        $r.status='FAILED'; $r.failureCode='NETWORK_COLLECTION_FAILED'; $r.failureLine=$_.InvocationInfo.ScriptLineNumber
        if ($_.Exception.Message -cmatch '^NETWORK_[A-Z_]+$') { $r.failureCode=$_.Exception.Message }
        Emit 'FAILED'
    }
}
function Read-PaperNetworkPinnedEvidence([string]$Path, [string]$Hash) {
    $full=Assert-PaperCustodyPath $Path
    if ((Get-Item -LiteralPath $full).Length -gt 2MB) { throw 'NETWORK_INPUT_LIMIT' }
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -cne $Hash) { throw 'NETWORK_INPUT_HASH_MISMATCH' }
    return Get-Content -LiteralPath $full -Raw | ConvertFrom-Json
}
function Assert-PaperNetworkSnapshot($Value) {
    if ($Value.version -cne 'PAPER_WRITER_NETWORK_SNAPSHOT_V1' -or $Value.status -cnotin @('RUNNING','FAILED','TARGETED_NETWORK_CAPTURED_REVIEW_REQUIRED')) { throw 'NETWORK_CHILD_CONTRACT' }
    foreach ($flag in @('configurationChanged','databaseContacted','writerLoginAttempted','actionExecutionEnabled','effectiveAccessProven','snapshotAtomic')) {
        if ($Value.$flag -isnot [bool] -or $Value.$flag) { throw 'NETWORK_CHILD_SAFETY' }
    }
    if ($Value.selectedRulesStableAtEnd -isnot [bool] -or @($Value.rules).Count -gt 2 -or @($Value.rulesAfter).Count -gt 2 -or $Value.ruleCount -ne @($Value.rules).Count -or @($Value.addresses).Count -gt 256 -or @($Value.adapters).Count -gt 128 -or @($Value.connectionProfiles).Count -gt 64 -or @($Value.firewallProfiles).Count -gt 3 -or @($Value.listeners).Count -gt 16 -or @($Value.queries).Count -gt 64) { throw 'NETWORK_CHILD_LIMIT' }
    foreach ($list in @('rules','rulesAfter')) {
        $names=@($Value.$list | ForEach-Object { $_.name })
        if (@($names | Select-Object -Unique).Count -ne $names.Count -or @($names | Where-Object { $_ -cnotin (Get-PaperNetworkTargetNames) }).Count) { throw 'NETWORK_CHILD_RULE_IDENTITIES' }
    }
    if ($Value.status -ceq 'TARGETED_NETWORK_CAPTURED_REVIEW_REQUIRED') {
        if ($Value.enumeratedRuleCount -lt 0 -or $Value.enumeratedRuleCount -gt 2000 -or $Value.enumeratedRuleCountAfter -lt 0 -or $Value.enumeratedRuleCountAfter -gt 2000 -or $Value.enumeratedRuleCount -lt @($Value.rules).Count -or $Value.enumeratedRuleCountAfter -lt @($Value.rulesAfter).Count) { throw 'NETWORK_CHILD_ENUMERATION_LIMIT' }
        if (@($Value.queries | Where-Object { $_.label -ceq 'FIREWALL_RULE_IDENTITIES' }).Count -ne 2) { throw 'NETWORK_CHILD_QUERY_COVERAGE' }
        foreach ($label in @('INTERFACE_ADDRESSES','ADAPTER_IDENTITIES','CONNECTION_PROFILES','FIREWALL_PROFILES','LISTENING_PORT_METADATA')) {
            if (@($Value.queries | Where-Object { $_.label -ceq $label }).Count -ne 1) { throw 'NETWORK_CHILD_QUERY_COVERAGE' }
        }
        foreach ($row in @($Value.rules)+@($Value.rulesAfter)) {
            foreach ($filter in @('port','address','application','service','interface','interfaceType','security')) {
                if ($null -eq $row.filters.PSObject.Properties[$filter]) { throw 'NETWORK_CHILD_FILTER_COVERAGE' }
            }
        }
        $missing=@(Get-PaperNetworkTargetNames | Where-Object { $_ -cnotin @($Value.rules | ForEach-Object { $_.name }) })
        if ((ConvertTo-Json -InputObject $missing -Compress) -cne (ConvertTo-Json -InputObject @($Value.missingRuleNames) -Compress)) { throw 'NETWORK_CHILD_MISSING_IDENTITIES' }
        $same=(ConvertTo-Json -InputObject $Value.rules -Depth 12 -Compress) -ceq (ConvertTo-Json -InputObject $Value.rulesAfter -Depth 12 -Compress)
        if ($same -ne $Value.selectedRulesStableAtEnd -or $Value.phase -cne 'COMPLETE' -or $Value.failureCode) { throw 'NETWORK_CHILD_COMPLETION' }
    }
}
