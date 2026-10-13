#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory)][string]$AccessReportPath,[Parameter(Mandatory)][string]$ExpectedHash)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
$watch=[Diagnostics.Stopwatch]::StartNew();$rows=[Collections.Generic.List[object]]::new()
$r=[ordered]@{version='PAPER_FIREWALL_SCOPE_V1';status='RUNNING';rules=@();expectedRuleCount=0;inspectedRuleCount=0;activeProfiles=@();listeners=@();listenerProcesses=@();ruleDriftDetected=$false;truncated=$true;configurationChanged=$false;effectiveAccessProven=$false;newRulesAssessed=$false;failureCode=$null;elapsedSeconds=0}
function Emit {
    $r.rules=$rows.ToArray();$r.inspectedRuleCount=$rows.Count;$r.elapsedSeconds=$watch.Elapsed.TotalSeconds
    $json=$r|ConvertTo-Json -Depth 10 -Compress
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 2MB){throw 'SCOPE_OUTPUT_LIMIT'}
    $json
}
function Deadline {if($watch.Elapsed.TotalSeconds -gt 150){throw 'SCOPE_TIME_LIMIT'}}
function One($Values){$items=@($Values);if($items.Count -ne 1){throw 'SCOPE_FILTER_CARDINALITY'};return $items[0]}
function Field($Object,[string]$Name){if($null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name};return $null}
try {
    $saved=Read-PaperRestrictionEvidence $AccessReportPath $ExpectedHash
    $names=@($saved.firewall.rules|ForEach-Object {$_.name})
    if($names.Count -gt 200 -or @($names|Select-Object -Unique).Count -ne $names.Count){throw 'SCOPE_RULE_LIMIT_OR_DUPLICATE'}
    $r.expectedRuleCount=$names.Count;Emit
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
    foreach($prior in @($saved.firewall.rules)){
        Deadline
        if($prior.name -isnot [string] -or -not $prior.name -or $prior.name.Length -gt 512 -or $prior.name -match '[\x00-\x1F*?\[\]]'){throw 'SCOPE_RULE_NAME_UNSAFE'}
        $rule=One @(Get-NetFirewallRule -PolicyStore ActiveStore -Name $prior.name)
        if($rule.Name -cne $prior.name){throw 'SCOPE_RULE_IDENTITY_MISMATCH'}
        $port=One @(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule)
        $addr=One @(Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule)
        $app=One @(Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule)
        $svc=One @(Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule)
        Deadline
        $interface=One @(Get-NetFirewallInterfaceFilter -AssociatedNetFirewallRule $rule)
        $interfaceType=One @(Get-NetFirewallInterfaceTypeFilter -AssociatedNetFirewallRule $rule)
        $security=One @(Get-NetFirewallSecurityFilter -AssociatedNetFirewallRule $rule)
        $current=[ordered]@{name=$rule.Name;action=[string]$rule.Action;profile=[string]$rule.Profile;protocol=[string]$port.Protocol;localPort=@($port.LocalPort);remotePort=@($port.RemotePort);localAddress=@($addr.LocalAddress);remoteAddress=@($addr.RemoteAddress);program=$app.Program;service=$svc.Service;edgeTraversal=[string]$rule.EdgeTraversalPolicy;policySourceType=[string]$rule.PolicyStoreSourceType}
        $drift=[string]$rule.Enabled -ne 'True' -or [string]$rule.Direction -ne 'Inbound'
        foreach($field in $current.Keys){
            if((@($current[$field]) -join '|') -cne (@($prior.$field) -join '|')){$drift=$true}
        }
        if($drift){$r.ruleDriftDetected=$true}
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
        if($rows.Count%20 -eq 0){Emit}
    }
    Deadline
    $r.status='SELECTORS_CAPTURED_REVIEW_REQUIRED';$r.truncated=$false
}catch{
    $r.status='FAILED';$r.failureCode='SCOPE_QUERY_FAILED'
    if($_.Exception.Message -cmatch '^SCOPE_[A-Z_]+$'){$r.failureCode=$_.Exception.Message}
}
Emit
if($r.status -ceq 'FAILED'){exit 2}
