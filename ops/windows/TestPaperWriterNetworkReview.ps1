# Offline only: all Windows network, process, credential and Git calls are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterNetworkReview.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
$script:checks=0; $script:mode='pass'; $script:ruleReads=0
function Check([bool]$Value,[string]$Label) { if (-not $Value) { throw $Label }; $script:checks++ }
function Get-NetFirewallRule {
    [CmdletBinding()]param($PolicyStore)
    Check ($PolicyStore -ceq 'ActiveStore') 'ActiveStore only'
    $script:ruleReads++
    if ($script:mode -ceq 'provider-error') { throw 'PRIVATE_ERROR_SENTINEL' }
    if ($script:mode -ceq 'rule-limit') { foreach($i in 1..2001){[pscustomobject]@{Name=('extra-'+$i)}};return }
    $names=Get-PaperNetworkTargetNames
    if ($script:mode -ceq 'missing-rule') { $names=@($names[0]) }
    if ($script:mode -ceq 'missing-all') { $names=@() }
    if ($script:mode -ceq 'duplicate') { $names+=@($names[0]) }
    foreach ($name in $names) {
        [pscustomobject]@{Name=$name;DisplayName='Synthetic private rule';Enabled=if($script:mode -ceq 'disabled'){'False'}else{'True'};Direction='Inbound';Action=if($script:mode -ceq 'rule-drift' -and $script:ruleReads -eq 2){'Block'}else{'Allow'};Profile='Domain, Private';PolicyStoreSourceType='Local';EdgeTraversalPolicy='Block';Description='PRIVATE_DESCRIPTION_SENTINEL'}
    }
}
function Get-NetFirewallPortFilter {
    [CmdletBinding()]param($AssociatedNetFirewallRule)
    if ($script:mode -ceq 'filter-error') { throw 'PRIVATE_ERROR_SENTINEL' }
    $v=[pscustomobject]@{Protocol='Any';LocalPort=@('Any');RemotePort=@('Any');DynamicTarget='Any'}
    $v; if($script:mode -ceq 'cardinality'){ $v }
}
function Get-NetFirewallAddressFilter {
    [CmdletBinding()]param($AssociatedNetFirewallRule)
    $first=$AssociatedNetFirewallRule.Name -ceq (Get-PaperNetworkTargetNames)[0]
    [pscustomobject]@{LocalAddress=if($script:mode -ceq 'dynamic-address'){@('LocalSubnet')}elseif($first){@('192.0.2.10')}else{@('2001:db8::10')};RemoteAddress=@('Any')}
}
function Get-NetFirewallApplicationFilter {
    [CmdletBinding()]param($AssociatedNetFirewallRule)
    if($script:mode -ceq 'missing-field'){ [pscustomobject]@{Program='Any'} }else{ [pscustomobject]@{Program='Any';Package=$null} }
}
function Get-NetFirewallServiceFilter { [CmdletBinding()]param($AssociatedNetFirewallRule); [pscustomobject]@{Service='Any'} }
function Get-NetFirewallInterfaceFilter { [CmdletBinding()]param($AssociatedNetFirewallRule); [pscustomobject]@{InterfaceAlias=@('Any')} }
function Get-NetFirewallInterfaceTypeFilter { [CmdletBinding()]param($AssociatedNetFirewallRule); [pscustomobject]@{InterfaceType=0} }
function Get-NetFirewallSecurityFilter { [CmdletBinding()]param($AssociatedNetFirewallRule); [pscustomobject]@{Authentication=0;Encryption=0;OverrideBlockRules=$false;LocalUser='Any';RemoteUser='Any';RemoteMachine='Any'} }
function Get-NetIPAddress {
    [CmdletBinding()]param()
    if($script:mode -ceq 'no-address'){return}
    $v=[pscustomobject]@{IPAddress='192.0.2.10';InterfaceIndex=23;InterfaceAlias='Synthetic VPN';AddressFamily=2;AddressState=4;PrefixLength=32}
    if($script:mode -ceq 'address-limit'){1..257|ForEach-Object{$v};return}
    $v
    [pscustomobject]@{IPAddress='2001:db8:0:0:0:0:0:10';InterfaceIndex=23;InterfaceAlias='Synthetic VPN';AddressFamily=23;AddressState=4;PrefixLength=128}
}
function Get-NetAdapter { [CmdletBinding()]param([switch]$IncludeHidden);Check $IncludeHidden 'Hidden adapters included';if($script:mode -ceq 'no-adapter'){return};[pscustomobject]@{ifIndex=23;Name='Synthetic VPN';InterfaceDescription='Synthetic adapter';Status='Up';MacAddress='PRIVATE_MAC_SENTINEL'} }
function Get-NetConnectionProfile { [CmdletBinding()]param();if($script:mode -ceq 'no-profile'){return};[pscustomobject]@{InterfaceIndex=23;InterfaceAlias='Synthetic VPN';NetworkCategory=1;IPv4Connectivity=4;IPv6Connectivity=4} }
function Get-NetFirewallProfile { [CmdletBinding()]param($PolicyStore);Check ($PolicyStore -ceq 'ActiveStore') 'Effective profile store';[pscustomobject]@{Name='Private';Enabled='True';DefaultInboundAction='Block';DefaultOutboundAction='Allow';AllowInboundRules='True';AllowLocalFirewallRules='True';DisabledInterfaceAliases=@()} }
function Get-NetTCPConnection { [CmdletBinding()]param($State);Check ($State -ceq 'Listen') 'No connection probe';if($script:mode -ceq 'no-listener'){return};[pscustomobject]@{LocalAddress='0.0.0.0';LocalPort=5432;OwningProcess=10} }
function Get-CimInstance { [CmdletBinding()]param($ClassName,$Filter);Check ($ClassName -ceq 'Win32_Process' -and $Filter -ceq 'ProcessId = 10') 'Exact listener process query';[pscustomobject]@{ProcessId=10;Name='postgres.exe';ExecutablePath='C:\synthetic\postgres.exe';CommandLine='PRIVATE_COMMAND_SENTINEL'} }
$script:last=$null
$successModes=@('pass','missing-rule','missing-all','disabled','rule-drift','dynamic-address','missing-field','no-address','no-adapter','no-profile','no-listener')
foreach ($mode in @($successModes)+@('provider-error','filter-error','cardinality','duplicate','rule-limit','address-limit')) {
    $script:mode=$mode; $script:ruleReads=0; $script:last=$null; $script:emissions=0
    Invoke-PaperWriterNetworkCollection { param($v)
        $script:last=$v|ConvertTo-Json -Depth 14 -Compress|ConvertFrom-Json
        Assert-PaperNetworkSnapshot $script:last
        $script:emissions++
    }
    Check ($null -ne $script:last) ($mode+': final report')
    Check ($script:emissions -le 5) 'Bounded checkpoints'
    Check ((ConvertTo-Json $script:last -Depth 14 -Compress) -notmatch 'PRIVATE_.*_SENTINEL') 'No raw error, MAC, command line or description'
    if ($mode -in $successModes) {
        Check ($script:last.status -ceq 'TARGETED_NETWORK_CAPTURED_REVIEW_REQUIRED') ($mode+': expected findings not collection error')
        Check ($script:ruleReads -eq 2) 'Rules checked twice'
        Check ($script:last.selectedRulesStableAtEnd -eq ($mode -ne 'rule-drift')) 'Selected rule drift retained'
        if($mode -ceq 'missing-rule'){Check ($script:last.missingRuleNames.Count -eq 1) 'Absent ID is a finding'}
        if($mode -ceq 'missing-all'){Check ($script:last.missingRuleNames.Count -eq 2) 'All absent IDs retained'}
        if($mode -ceq 'pass'){
            Check ($script:last.addressLinks.Count -eq 2) 'Both IP families mapped'
            foreach($link in $script:last.addressLinks){Check ($link.status -ceq 'ADDRESS_OBSERVED_ON_INTERFACE' -and $link.matches.Count -eq 1) 'Canonical IP equality';Check ($link.matches[0].adapters.Count -eq 1 -and $link.matches[0].connectionProfiles.Count -eq 1) 'Interface joins'}
            $script:good=$script:last|ConvertTo-Json -Depth 14 -Compress
        }
        if($mode -ceq 'missing-field'){Check ($script:last.rules[0].missingFields -contains 'application.Package') 'Missing versus null field'}
        if($mode -ceq 'no-address'){Check ($script:last.addressLinks[0].status -ceq 'ADDRESS_NOT_OBSERVED') 'Missing address not assumed safe'}
        if($mode -ceq 'dynamic-address'){Check ($script:last.addressLinks[0].status -ceq 'NON_LITERAL_SELECTOR_REQUIRES_REVIEW') 'No guessed subnet semantics'}
    } else { Check ($script:last.status -ceq 'FAILED' -and $script:last.failureCode -like 'NETWORK_*') ($mode+': safe failure') }
}
foreach($mutation in @('configurationChanged','databaseContacted','writerLoginAttempted','actionExecutionEnabled','effectiveAccessProven','snapshotAtomic','missingRuleNames','selectedRulesStableAtEnd','ruleCount','ruleIdentity','enumerationLimit','queryCoverage','filterCoverage')) {
    $v=$script:good|ConvertFrom-Json
    switch($mutation){
        'missingRuleNames'{$v.missingRuleNames=@('invented')}
        'selectedRulesStableAtEnd'{$v.selectedRulesStableAtEnd=$false}
        'ruleCount'{$v.ruleCount=0}
        'ruleIdentity'{$v.rules[0].name='unexpected'}
        'enumerationLimit'{$v.enumeratedRuleCount=2001}
        'queryCoverage'{$v.queries=@()}
        'filterCoverage'{$v.rules[0].filters.PSObject.Properties.Remove('application')}
        default{$v.$mutation=$true}
    }
    $rejected=$false;try{Assert-PaperNetworkSnapshot $v}catch{$rejected=$true}
    Check $rejected ('Reject tampered '+$mutation)
}
# Exercise the real parent script/report lifecycle with synthetic input and child output.
$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GetPaperWriterNetworkReview.ps1') -Raw
$text=$text.Replace('#Requires -Version 7.0','')
$text=[regex]::Replace($text,'(?m)^\. \(Join-Path \$PSScriptRoot ''[^'']+''\)\r?\n','')
$text=$text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$text=[regex]::Replace($text,'(?m)^    \$principal=.*\r?\n','')
$text=[regex]::Replace($text,'(?m)^    if \(-not \$principal\.IsInRole.*\r?\n','')
$parent=[scriptblock]::Create($text)
function git { $global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'synthetic-revision'} }
function Read-PaperNetworkPinnedEvidence($Path,$Hash) {
    if($script:mode -ceq 'bad-input'){throw 'NETWORK_INPUT_HASH_MISMATCH'}
    if($Hash -ceq 'E540CC1DABE3C2014FCD01D01C3B4A53ABC4C608D4708F75B9CF47C83C316144'){[pscustomobject]@{status='HBA_RESTRICTION_STAGED_WRITER_DISABLED'}}
    elseif($Hash -ceq '9B1B2C9E4B3D87F8C7F6D37BD2C8798AF637A7406AB11A42DF23A841BCA9000E'){[pscustomobject]@{status='PREPARATION_CAPTURED_STAGING_BLOCKED'}}
    else{throw 'Unknown evidence pin'}
}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds) {
    Check ($LimitSeconds -eq 150 -and $Arguments -contains '-Collect' -and $Arguments -contains '-NonInteractive') 'Bounded metadata-only child'
    $output=$script:good
    if($script:mode -ceq 'malformed'){$output='PRIVATE_NOT_JSON_SENTINEL'}
    if($script:mode -ceq 'unsafe'){$v=$output|ConvertFrom-Json;$v.actionExecutionEnabled=$true;$output=$v|ConvertTo-Json -Depth 14 -Compress}
    if($script:mode -ceq 'too-many'){$output=(@($output)*6)-join "`n"}
    [pscustomobject]@{exitCode=if($script:mode -ceq 'exit-error'){1}else{0};timedOut=($script:mode -ceq 'timeout');elapsedSeconds=1;stdout=$output;stderr='PRIVATE_STDERR_SENTINEL'}
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-network-review-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
foreach($mode in @('pass','bad-input','malformed','unsafe','too-many','exit-error','timeout')) {
    $script:mode=$mode; $case=Join-Path $work $mode
    $failed=$false;try{& $parent -OutputDirectory $case}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $case -Filter '*.json')
    Check ($files.Count -eq 1) ($mode+': exactly one report')
    $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    Check ($failed -eq ($mode -ne 'pass')) ($mode+': parent fail-stop')
    Check ($r.status -ceq $(if($mode -ceq 'pass'){'NETWORK_REVIEW_CAPTURED_ACTIVATION_BLOCKED'}else{'FAILED'})) 'Parent status'
    Check (-not $r.configurationChanged -and -not $r.activationAuthorized -and -not $r.databaseContacted) 'No mutation or credential authority'
    Check ((ConvertTo-Json $r -Depth 16 -Compress) -notmatch 'PRIVATE_.*_SENTINEL') 'Sanitized parent report'
    # Remove only the exact generated report and now-empty test directories.
    if(-not $files[0].FullName.StartsWith($work+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture path escaped'}
    Remove-Item -LiteralPath $files[0].FullName
    [IO.Directory]::Delete($case,$false)
}
[IO.Directory]::Delete($work,$false)
[pscustomobject]@{status='PASSED';assertions=$script:checks;collectorScenarios=17;parentScenarios=7;realNetworkQueried=$false;databaseContacted=$false;configurationChanged=$false;fixtureCleanupComplete=$true}
