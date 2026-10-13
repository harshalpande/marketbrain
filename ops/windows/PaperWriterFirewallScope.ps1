#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory)][string]$AccessReportPath,[Parameter(Mandatory)][string]$ExpectedHash)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
$watch=[Diagnostics.Stopwatch]::StartNew();$rows=[Collections.Generic.List[object]]::new()
$r=[ordered]@{version='PAPER_FIREWALL_SCOPE_V2';status='RUNNING';rules=@();expectedRuleCount=0;inspectedRuleCount=0;activeProfiles=@();listeners=@();listenerProcesses=@();ruleDriftDetected=$false;truncated=$true;configurationChanged=$false;effectiveAccessProven=$false;newRulesAssessed=$false;failureCode=$null;elapsedSeconds=0}
$r['collectorRevision']=4
$r['limits']=@{softSeconds=300;parentSeconds=330;candidateRules=200;inboundRules=2000}
$r['ruleLookupCalls']=0;$r['filterQueryCalls']=0;$r['queryTimings']=@{}
$r['phase']='INPUT';$r['activeRuleName']=$null
$r['inboundRulesEnumerated']=0;$r['missingRuleNames']=@();$r['diagnostic']=$null
$r['scannedRuleCount']=0;$r['matchedSavedRuleCount']=0;$r['currentRelevantRuleCount']=0
$r['unbaselinedCandidateNames']=@();$r['currentCandidatesCollected']=$false;$r['ruleSetStableAtEnd']=$false
$r['snapshotAtomic']=$false
function Emit {
    $r.rules=$rows.ToArray();$r.inspectedRuleCount=$rows.Count;$r.elapsedSeconds=$watch.Elapsed.TotalSeconds
    $json=$r|ConvertTo-Json -Depth 10 -Compress
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 2MB){throw 'SCOPE_OUTPUT_LIMIT'}
    $json
}
function Deadline {if($watch.Elapsed.TotalSeconds -gt 300){throw 'SCOPE_TIME_LIMIT'}}
function One($Values){$items=@($Values);if($items.Count -ne 1){throw 'SCOPE_FILTER_CARDINALITY'};return $items[0]}
function Field($Object,[string]$Name){if($null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name};return $null}
function Port-Relevant($Port){
    # Exclude only known non-TCP protocols/ports. Unknown or dynamic selectors stay candidates.
    $protocol=[string](Field $Port 'Protocol')
    if($protocol -match '^\d{1,3}$' -and [int]$protocol -le 255 -and [int]$protocol -ne 6){return $false}
    if($protocol -in @('UDP','ICMPv4','ICMPv6')){return $false}
    if($protocol -notin @('TCP','6','Any','256')){return $true}
    $ports=@(Field $Port 'LocalPort');if(-not $ports.Count){return $true}
    foreach($value in $ports){
        $p=[string]$value
        if($p -match '^\d{1,5}$' -and [int]$p -le 65535){if([int]$p -eq 5432){return $true};continue}
        if($p -match '^(\d{1,5})-(\d{1,5})$'){
            $lo=[int]$Matches[1];$hi=[int]$Matches[2]
            if($lo -gt $hi -or $hi -gt 65535){return $true}
            if($lo -le 5432 -and $hi -ge 5432){return $true};continue
        }
        return $true
    }
    return $false
}
function Read-InboundRules {
    Deadline;$r.ruleLookupCalls++;$clock=[Diagnostics.Stopwatch]::StartNew()
    try {$values=@(Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound|Select-Object -First 2001)}
    finally {
        if(-not $r.queryTimings.ContainsKey('Get-NetFirewallRule')){$r.queryTimings['Get-NetFirewallRule']=@{calls=0;elapsedSeconds=0.0}}
        $r.queryTimings['Get-NetFirewallRule'].calls++;$r.queryTimings['Get-NetFirewallRule'].elapsedSeconds+=$clock.Elapsed.TotalSeconds
    }
    if($values.Count -gt 2000){throw 'SCOPE_INBOUND_RULE_LIMIT'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($value in $values){
        if($value.Name -isnot [string] -or -not $value.Name -or $value.Name.Length -gt 512 -or $value.Name -match '[\x00-\x1F]' -or -not $seen.Add($value.Name) -or [string]$value.Enabled -cne 'True' -or [string]$value.Direction -cne 'Inbound'){throw 'SCOPE_RULE_IDENTITY_MISMATCH'}
    }
    Deadline
    return $values
}
function Rule-Signature($Rules){
    return (@($Rules|Sort-Object -Property Name|Select-Object Name,Enabled,Direction,Action,Profile,EdgeTraversalPolicy,PolicyStoreSourceType)|ConvertTo-Json -Depth 4 -Compress)
}
function Safe-Diagnostic($Record){
    # Machine codes only. Never capture message, target, command arguments, stack or raw stderr.
    $code=[string]$Record.FullyQualifiedErrorId
    if($code.Length -gt 200 -or $code -cnotmatch '^(?:SCOPE_[A-Z_]+|(?:CimJob_|CmdletizationQuery_|Parameter)[A-Za-z0-9_]+(?:,[A-Za-z0-9_.-]+)?|PropertyNotFoundStrict|InvalidOperation|ArgumentException|MethodInvocationException)$'){$code='REDACTED_NON_CODE_ERROR_ID'}
    return @{errorId=$code;category=[string]$Record.CategoryInfo.Category;exceptionType=$Record.Exception.GetType().FullName;hresult=$Record.Exception.HResult;scriptLine=$Record.InvocationInfo.ScriptLineNumber}
}
function Read-ScopedFilter([string]$Command,$Rule){
    Deadline
    $r.phase=$Command;$r.filterQueryCalls++
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try {$result=One @(& $Command -AssociatedNetFirewallRule $Rule)}
    finally {
        if(-not $r.queryTimings.ContainsKey($Command)){$r.queryTimings[$Command]=@{calls=0;elapsedSeconds=0.0}}
        $r.queryTimings[$Command].calls++;$r.queryTimings[$Command].elapsedSeconds+=$clock.Elapsed.TotalSeconds
    }
    Deadline
    return $result
}
try {
    $saved=Read-PaperRestrictionEvidence $AccessReportPath $ExpectedHash
    $names=@($saved.firewall.rules|ForEach-Object {$_.name})
    if($names.Count -gt 200 -or @($names|Select-Object -Unique).Count -ne $names.Count){throw 'SCOPE_RULE_LIMIT_OR_DUPLICATE'}
    foreach($name in $names){
        if($name -isnot [string] -or -not $name -or $name.Length -gt 512 -or $name -match '[\x00-\x1F*?\[\]]'){throw 'SCOPE_RULE_NAME_UNSAFE'}
    }
    $r.expectedRuleCount=$names.Count;Emit
    $r.phase='LISTENER_AND_PROFILE_METADATA'
    $r.activeProfiles=@(Get-NetConnectionProfile|Select-Object -First 33 -Property InterfaceIndex,NetworkCategory,IPv4Connectivity,IPv6Connectivity)
    if($r.activeProfiles.Count -gt 32){throw 'SCOPE_PROFILE_LIMIT'}
    Deadline
    $r.listeners=@(Get-NetTCPConnection -State Listen -LocalPort 5432|Select-Object -First 17 -Property LocalAddress,LocalPort,OwningProcess)
    if($r.listeners.Count -eq 0 -or $r.listeners.Count -gt 16){throw 'SCOPE_LISTENER_MISSING_OR_LIMIT'}
    $processes=[Collections.Generic.List[object]]::new()
    foreach($owner in @($r.listeners|Select-Object -ExpandProperty OwningProcess -Unique)){
        Deadline
        if([string]$owner -cnotmatch '^[0-9]{1,10}$'){throw 'SCOPE_PROCESS_ID_INVALID'}
        # Never retain CommandLine, which may contain unrelated secrets.
        $p=One @(Get-CimInstance Win32_Process -Filter ("ProcessId = "+$owner))
        $processes.Add([pscustomobject]@{processId=$owner;name=$p.Name;executablePath=$p.ExecutablePath})
    }
    $r.listenerProcesses=$processes.ToArray()
    $r.phase='RULE_LOOKUP';Emit;Deadline
    # Inspect all current enabled-inbound port filters, not only stale saved IDs.
    # Retain actual CIM objects; never substitute a similar-looking replacement rule.
    $currentRules=@(Read-InboundRules);$initialSignature=Rule-Signature $currentRules
    $r.inboundRulesEnumerated=$currentRules.Count
    $currentNames=@($currentRules|ForEach-Object {$_.Name})
    $r.missingRuleNames=@($names|Where-Object {$currentNames -cnotcontains $_})
    if($r.missingRuleNames.Count){$r.ruleDriftDetected=$true}
    $priorMap=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($prior in @($saved.firewall.rules)){$priorMap.Add($prior.name,$prior)}
    Deadline
    foreach($rule in $currentRules){
        Deadline
        $r.activeRuleName=$rule.Name
        $port=Read-ScopedFilter 'Get-NetFirewallPortFilter' $rule
        $relevant=Port-Relevant $port;$hasPrior=$priorMap.ContainsKey($rule.Name)
        if(-not $relevant -and -not $hasPrior){
            $r.scannedRuleCount++
            if($r.scannedRuleCount%100 -eq 0){Emit}
            continue
        }
        if($rows.Count -ge 200){throw 'SCOPE_CURRENT_CANDIDATE_LIMIT'}
        $addr=Read-ScopedFilter 'Get-NetFirewallAddressFilter' $rule
        $app=Read-ScopedFilter 'Get-NetFirewallApplicationFilter' $rule
        $svc=Read-ScopedFilter 'Get-NetFirewallServiceFilter' $rule
        $interface=Read-ScopedFilter 'Get-NetFirewallInterfaceFilter' $rule
        $interfaceType=Read-ScopedFilter 'Get-NetFirewallInterfaceTypeFilter' $rule
        $security=Read-ScopedFilter 'Get-NetFirewallSecurityFilter' $rule
        $current=[ordered]@{name=$rule.Name;action=[string]$rule.Action;profile=[string]$rule.Profile;protocol=[string]$port.Protocol;localPort=@($port.LocalPort);remotePort=@($port.RemotePort);localAddress=@($addr.LocalAddress);remoteAddress=@($addr.RemoteAddress);program=$app.Program;service=$svc.Service;edgeTraversal=[string]$rule.EdgeTraversalPolicy;policySourceType=[string]$rule.PolicyStoreSourceType}
        $drift=$false
        if($hasPrior){
            $prior=$priorMap[$rule.Name]
            foreach($field in $current.Keys){
                if((@($current[$field]) -join '|') -cne (@($prior.$field) -join '|')){$drift=$true}
            }
        }
        if($drift){$r.ruleDriftDetected=$true}
        $current['presentInSavedCandidates']=$hasPrior;$current['portRelevantNow']=$relevant
        $current['enabled']=[string]$rule.Enabled;$current['direction']=[string]$rule.Direction;$current['driftFromSavedEvidence']=$drift
        $current['package']=Field $app 'Package';$current['packageFieldPresent']=$null -ne $app.PSObject.Properties['Package']
        $current['interfaceAlias']=@(Field $interface 'InterfaceAlias');$current['interfaceType']=@(Field $interfaceType 'InterfaceType')
        $current['security']=$security|Select-Object Authentication,Encryption,OverrideBlockRules,LocalUser,RemoteUser,RemoteMachine
        $current['missingSelectorFields']=@(
            foreach($pair in @(@($app,'Package'),@($interface,'InterfaceAlias'),@($interfaceType,'InterfaceType'),@($security,'Authentication'),@($security,'Encryption'),@($security,'OverrideBlockRules'),@($security,'LocalUser'),@($security,'RemoteUser'),@($security,'RemoteMachine'))){
                if($null -eq $pair[0].PSObject.Properties[$pair[1]]){$pair[1]}
            }
        )
        $rows.Add([pscustomobject]$current)
        if($hasPrior){$r.matchedSavedRuleCount++}else{$r.unbaselinedCandidateNames+=@($rule.Name);$r.ruleDriftDetected=$true}
        if($relevant){$r.currentRelevantRuleCount++}
        $r.scannedRuleCount++
        if($rows.Count%20 -eq 0 -or $r.scannedRuleCount%100 -eq 0){Emit}
    }
    Deadline
    $r.phase='FINAL_RULE_SET_CHECK';$r.activeRuleName=$null;Emit
    if((Rule-Signature @(Read-InboundRules)) -cne $initialSignature){throw 'SCOPE_RULE_SET_CHANGED_DURING_COLLECTION'}
    $r.ruleSetStableAtEnd=$true;$r.currentCandidatesCollected=$true
    $r.phase='COMPLETE';$r.activeRuleName=$null
    $r.status='SELECTORS_CAPTURED_REVIEW_REQUIRED';$r.truncated=$false
}catch{
    $r.status='FAILED';$r.failureCode='SCOPE_QUERY_FAILED'
    $r.diagnostic=Safe-Diagnostic $_
    if($_.Exception.Message -cmatch '^SCOPE_[A-Z_]+$'){$r.failureCode=$_.Exception.Message}
}
Emit
if($r.status -ceq 'FAILED'){exit 2}
