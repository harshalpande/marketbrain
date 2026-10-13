# All OS, firewall, process and git calls are mocked. Actual runner/report code is exercised.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
$script:checks=0
function Check([bool]$Ok,[string]$Name){if(-not $Ok){throw $Name};$script:checks++}
function Get-OfflineScript([string]$Name){
    $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot $Name) -Raw
    $text=$text.Replace('#Requires -Version 7.0','')
    $text=[regex]::Replace($text,'(?m)^\. \(Join-Path \$PSScriptRoot ''[^'']+''\)\r?\n','')
    $text=$text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
    $text=[regex]::Replace($text,'(?m)^    \$principal=.*\r?\n','')
    $text=[regex]::Replace($text,'(?m)^    if\(-not \$principal\.IsInRole.*\r?\n','')
    $text=$text.Replace("if(`$r.status -ceq 'FAILED'){exit 2}",'')
    # Virtual elapsed clock: exercise the actual soft-deadline branch without sleeping.
    $text=$text.Replace('$watch.Elapsed.TotalSeconds -gt 300','$(if($script:mode -ceq ''soft-timeout'' -and $rows.Count -ge 92){301}elseif($script:mode -ceq ''past-old-deadline''){200}else{$watch.Elapsed.TotalSeconds}) -gt 300')
    return [scriptblock]::Create($text)
}
$child=Get-OfflineScript 'PaperWriterFirewallScope.ps1';$runner=Get-OfflineScript 'GetPaperWriterRestrictionPreparation.ps1'
# Exercise the actual pure classifier with adversarial/dynamic selectors, no OS access.
$ast=[Management.Automation.Language.Parser]::ParseInput($child.ToString(),[ref]$null,[ref]$null)
foreach($name in @('Field','Port-Relevant')){
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
foreach($case in @(
    @('TCP',@('5432'),$true),@('6',@('5400-5500'),$true),@('TCP',@('443'),$false),
    @('UDP',@('5432'),$false),@('17',@('Any'),$false),@('Any',@('Any'),$true),
    @('256',@('5432'),$true),@('TCP',@('RPC'),$true),@('TCP',@(),$true),
    @('TCP',@(''),$true),@('unknown',@('443'),$true),@('999',@('443'),$true),
    @('TCP',@('65536'),$true),@('TCP',@('6000-5000'),$true),@('TCP',@('1-65536'),$true),
    @('TCP',@('1-5431'),$false),@('TCP',@('5433-65535'),$false),@('TCP',@('443','5432'),$true)
)){
    Check ((Port-Relevant ([pscustomobject]@{Protocol=$case[0];LocalPort=$case[1]})) -eq $case[2]) 'Conservative port classification'
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-restriction-runner-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:saved=[pscustomobject]@{runId='synthetic';firewall=@{rules=@()}}
$script:mode='pass'
function Read-PaperRestrictionEvidence($Path,$ExpectedHash){
    Check ($ExpectedHash -ceq 'FFFF18099697737091CB1A8B031AA5ED8F6ACE4C9567DECA6F54C60A11962650') 'Pinned accepted input'
    if($script:mode -ceq 'bad-evidence'){throw 'RESTRICTION_EVIDENCE_HASH_MISMATCH'}
    return $script:saved
}
function Get-NetConnectionProfile {[pscustomobject]@{InterfaceIndex=1;NetworkCategory='Private';IPv4Connectivity='Internet';IPv6Connectivity='NoTraffic'}}
function Get-NetTCPConnection {param($State,$LocalPort);Check ($State -ceq 'Listen' -and $LocalPort -eq 5432) 'Exact listener only';if($script:mode -eq 'no-listener'){return};[pscustomobject]@{LocalAddress='127.0.0.1';LocalPort=5432;OwningProcess=10}}
function Get-CimInstance {param($ClassName,$Filter);Check ($ClassName -ceq 'Win32_Process' -and $Filter -ceq 'ProcessId = 10') 'Exact listener process';[pscustomobject]@{Name='postgres.exe';ExecutablePath='C:\synthetic\postgres.exe';CommandLine='SECRET_SENTINEL'}}
function Get-NetFirewallRule {[CmdletBinding()]param($PolicyStore,$Enabled,$Direction,$Name)
    $script:queries++
    if($PSBoundParameters.ContainsKey('Name')){throw 'MULTI_NAME_PROVIDER_QUERY_MUST_NOT_BE_USED'}
    Check ($PolicyStore -ceq 'ActiveStore' -and $Enabled -ceq 'True' -and $Direction -ceq 'Inbound') 'Bounded enabled inbound enumeration, no multi-name query'
    if($script:mode -ceq 'provider-error'){
        $record=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('SECRET_SENTINEL'),'CimJob_ProviderFailure',[Management.Automation.ErrorCategory]::InvalidOperation,'SECRET_SENTINEL')
        $PSCmdlet.ThrowTerminatingError($record)
    }
    if($script:mode -ceq 'inbound-limit'){$items=1..2001|ForEach-Object {'extra-'+$_}}else{$items=@($script:saved.firewall.rules|ForEach-Object {$_.name})+@('unrelated-inbound')}
    if($script:mode -ceq 'two-replacements'){$items=@($items|Where-Object {$_ -notin @('rule-2','rule-3')})+@('replacement-a','replacement-b')}
    if($script:mode -ceq 'all-missing'){$items=@('unrelated-inbound')}
    if($script:mode -in @('new-rule','candidate-limit','new-port-fail')){$items+=@('new-rule')}
    if($script:mode -ceq 'live-change' -and $script:queries -eq 2){$items+=@('late-rule')}
    foreach($n in $items){
        if($script:mode -ceq 'missing-rule' -and $n -ceq 'rule-2'){continue}
        $v=[pscustomobject]@{Name=$n;Action='Allow';Profile='Any';Enabled='True';Direction='Inbound';EdgeTraversalPolicy='Block';PolicyStoreSourceType='Local'}
        if($script:mode -ceq 'drift'){$v.Action='Block'}
        if($script:mode -ceq 'unexpected-rule' -and $n -ceq 'rule-2'){$v.Name='unrelated'}
        if($script:mode -ceq 'duplicate-rule' -and $n -ceq 'rule-2'){$v.Name='rule-1'}
        if($script:mode -ceq 'case-mismatch' -and $n -ceq 'rule-2'){$v.Name='RULE-2'}
        $v;if($script:mode -ceq 'ambiguous'){$v}
    }
}
function Get-NetFirewallPortFilter {
    param($AssociatedNetFirewallRule)
    if(($script:mode -ceq 'query-fail' -and $AssociatedNetFirewallRule.Name -ceq 'rule-22') -or ($script:mode -ceq 'new-port-fail' -and $AssociatedNetFirewallRule.Name -ceq 'new-rule')){throw 'SECRET_SENTINEL'}
    $port='Any'
    if($AssociatedNetFirewallRule.Name -ceq 'unrelated-inbound' -or ($script:mode -ceq 'became-irrelevant' -and $AssociatedNetFirewallRule.Name -ceq 'rule-2')){$port='443'}
    [pscustomobject]@{Protocol='TCP';LocalPort=@($port);RemotePort=@('Any')}
}
function Get-NetFirewallAddressFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{LocalAddress=@('Any');RemoteAddress=@('Any')}}
function Get-NetFirewallApplicationFilter {param($AssociatedNetFirewallRule);if($script:mode -ceq 'missing-package'){[pscustomobject]@{Program='Any'}}else{[pscustomobject]@{Program='Any';Package='test-package'}}}
function Get-NetFirewallServiceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Service='Any'}}
function Get-NetFirewallInterfaceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{InterfaceAlias=@('Any')}}
function Get-NetFirewallInterfaceTypeFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{InterfaceType=@('Any')}}
function Get-NetFirewallSecurityFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Authentication='NotRequired';Encryption='NotRequired';OverrideBlockRules=$false;LocalUser='Any';RemoteUser='Any';RemoteMachine='Any'}}
$maximum=@(1..200|ForEach-Object {[pscustomobject]@{name=('rule-'+$_);action='Allow';profile='Any';protocol='TCP';localPort=@('Any');remotePort=@('Any');localAddress=@('Any');remoteAddress=@('Any');program='Any';service='Any';edgeTraversal='Block';policySourceType='Local'}})
$normal=@($maximum|Select-Object -First 126)
$script:captured=@{}
$successModes=@('pass','pass-200','past-old-deadline','drift','missing-rule','unexpected-rule','case-mismatch','missing-package','two-replacements','new-rule','became-irrelevant','empty-baseline','all-missing')
foreach($script:mode in ($successModes+@('ambiguous','duplicate-rule','query-fail','soft-timeout','no-listener','unsafe-name','limit','provider-error','inbound-limit','candidate-limit','live-change','new-port-fail'))){
    $script:saved.firewall.rules=$normal;$script:queries=0
    if($script:mode -in @('pass-200','candidate-limit')){$script:saved.firewall.rules=$maximum}
    if($script:mode -ceq 'empty-baseline'){$script:saved.firewall.rules=@()}
    if($script:mode -ceq 'unsafe-name'){$script:saved.firewall.rules=@([pscustomobject]@{name='*'})}
    if($script:mode -ceq 'limit'){$script:saved.firewall.rules=$normal+$normal}
    $lines=@(& $child -AccessReportPath 'unused' -ExpectedHash 'FFFF18099697737091CB1A8B031AA5ED8F6ACE4C9567DECA6F54C60A11962650')
    $raw=$lines -join "`n";$v=$lines[-1]|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No process command line or raw error retained'
    Check (-not $v.configurationChanged -and -not $v.effectiveAccessProven -and -not $v.newRulesAssessed) 'No access assertion'
    if($script:mode -in $successModes){
        Check ($v.status -ceq 'SELECTORS_CAPTURED_REVIEW_REQUIRED' -and -not $v.truncated -and $v.currentCandidatesCollected -and $v.ruleSetStableAtEnd -and -not $v.snapshotAtomic) 'Complete bounded comparison, never atomic or approved'
        Check ($v.ruleDriftDetected -eq ($script:mode -in @('drift','missing-rule','unexpected-rule','case-mismatch','two-replacements','new-rule','became-irrelevant','all-missing'))) 'Drift reported'
        Check ($script:queries -eq 2 -and $v.ruleLookupCalls -eq 2) 'Bounded start and end enumeration'
        Check ($v.scannedRuleCount -eq $v.inboundRulesEnumerated -and @($v.rules|ForEach-Object {$_.name}) -notcontains 'unrelated-inbound') 'Every inbound port scanned; unrelated rule excluded from detailed evidence'
        Check ($v.filterQueryCalls -eq ($v.inboundRulesEnumerated+6*$v.inspectedRuleCount)) 'All seven associations retained without querying port twice'
        Check ($v.matchedSavedRuleCount+$v.missingRuleNames.Count -eq $script:saved.firewall.rules.Count) 'Saved identities reconciled without replacement substitution'
        Check ($v.limits.softSeconds -eq 300 -and $v.limits.parentSeconds -eq 330) 'Bounded timing telemetry'
        if($script:mode -notin @('empty-baseline','all-missing')){Check (@($v.queryTimings.PSObject.Properties).Count -eq 8) 'All association command timings'}
        $script:captured[$script:mode]=$lines[-1]
        if($script:mode -ceq 'two-replacements'){
            Check ($v.missingRuleNames.Count -eq 2 -and $v.matchedSavedRuleCount -eq 124 -and $v.unbaselinedCandidateNames.Count -eq 2 -and $v.inspectedRuleCount -eq 126) 'Reproduces two absent IDs with two fully inspected current candidates'
        }
        if($script:mode -ceq 'became-irrelevant'){Check (-not ($v.rules|Where-Object name -eq 'rule-2').portRelevantNow -and $v.currentRelevantRuleCount -eq 125) 'Saved rule becoming irrelevant retained as changed evidence'}
        if($script:mode -in @('missing-rule','unexpected-rule','case-mismatch')){Check ($v.missingRuleNames -ccontains 'rule-2') 'Missing exact identity retained'}
        if($script:mode -ceq 'pass'){
            Check ($v.rules[0].package -ceq 'test-package' -and $v.rules[0].program -ceq 'Any') 'Package not confused with program'
            Check ($v.rules[0].interfaceAlias[0] -ceq 'Any' -and $v.rules[0].security.Authentication -ceq 'NotRequired') 'Missing selectors now retained'
            Check ($v.listeners.Count -eq 1 -and $v.listenerProcesses.Count -eq 1 -and $v.activeProfiles.Count -eq 1) 'Listener/profile metadata captured'
            $script:successJson=$lines[-1]
            $script:partialJson=$lines[2]
        }
        if($script:mode -ceq 'missing-package'){Check ($v.rules[0].missingSelectorFields -contains 'Package') 'Unknown selector explicit'}
    }else{
        Check ($v.status -ceq 'FAILED' -and $v.truncated -and $v.failureCode) 'Failure not success'
        if($script:mode -ceq 'query-fail'){Check ($v.rules.Count -eq 21 -and $v.failureCode -ceq 'SCOPE_QUERY_FAILED') 'Partial checkpoints retained'}
        if($script:mode -ceq 'soft-timeout'){Check ($v.rules.Count -eq 92 -and $v.failureCode -ceq 'SCOPE_TIME_LIMIT') 'Soft deadline preserves 92 rows'}
        if($script:mode -in @('duplicate-rule','ambiguous')){Check ($v.filterQueryCalls -eq 0) 'Duplicate identity set stops before filters'}
        if($script:mode -ceq 'live-change'){Check ($v.failureCode -ceq 'SCOPE_RULE_SET_CHANGED_DURING_COLLECTION' -and -not $v.currentCandidatesCollected) 'Rule set changing mid-run cannot pass'}
        if($script:mode -ceq 'candidate-limit'){Check ($v.failureCode -ceq 'SCOPE_CURRENT_CANDIDATE_LIMIT') 'Current candidate overflow cannot pass'}
        if($script:mode -ceq 'new-port-fail'){Check ($v.failureCode -ceq 'SCOPE_QUERY_FAILED' -and -not $v.currentCandidatesCollected) 'Failure inspecting new rule cannot be skipped'}
        if($script:mode -ceq 'provider-error'){
            Check ($v.phase -ceq 'RULE_LOOKUP' -and $v.diagnostic.errorId -match '^CimJob_ProviderFailure' -and $v.diagnostic.hresult -lt 0) 'Safe provider codes retained'
            $script:providerFailureJson=$lines[-1]
        }
        if($script:mode -ceq 'inbound-limit'){Check ($v.failureCode -ceq 'SCOPE_INBOUND_RULE_LIMIT' -and $v.filterQueryCalls -eq 0) 'Bounded enumeration stops before filters'}
    }
}
function git {$global:LASTEXITCODE=0;if($args -contains 'status' -and $script:mode -ceq 'dirty'){' M own.txt'};if($args -contains 'rev-parse'){'a'*40}}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
    $script:childCalls++;Check ($LimitSeconds -eq 330 -and $Arguments -contains '-NonInteractive') 'Bounded noninteractive child'
    $stdout=$script:successJson;$exit=0;$timedOut=$false
    switch($script:mode){
        'timeout' {$stdout=$script:partialJson+"`n{";$exit=-999;$timedOut=$true}
        'malformed' {$stdout=$script:successJson+"`nnot-json"}
        'failed-child' {$exit=2}
        'provider-error' {$exit=2;$stdout=$script:providerFailureJson}
        'bad-count' {$v=$stdout|ConvertFrom-Json;$v.inspectedRuleCount=0;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'drift' {$v=$stdout|ConvertFrom-Json;$v.ruleDriftDetected=$true;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'two-replacements' {$stdout=$script:captured['two-replacements']}
        'all-missing' {$stdout=$script:captured['all-missing']}
        'omitted-missing' {$v=$script:captured['two-replacements']|ConvertFrom-Json;$v.missingRuleNames=@();$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'unscanned' {$v=$stdout|ConvertFrom-Json;$v.scannedRuleCount--;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'duplicate-output' {$v=$stdout|ConvertFrom-Json;$v.rules[1]=$v.rules[0];$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'false-completion' {$v=$stdout|ConvertFrom-Json;$v.currentCandidatesCollected=$false;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'unreported-new' {$v=$script:captured['two-replacements']|ConvertFrom-Json;$v.unbaselinedCandidateNames=@();$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'old-contract' {$v=$stdout|ConvertFrom-Json;$v.version='PAPER_FIREWALL_SCOPE_V1';$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'no-final-check' {$v=$stdout|ConvertFrom-Json;$v.ruleSetStableAtEnd=$false;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
    }
    [pscustomobject]@{stdout=$stdout;stderr='SECRET_SENTINEL';exitCode=$exit;timedOut=$timedOut;elapsedSeconds=0.01}
}
$script:saved.firewall.rules=$normal
foreach($script:mode in @('pass','drift','two-replacements','all-missing','dirty','bad-evidence','timeout','malformed','failed-child','bad-count','provider-error','omitted-missing','unscanned','duplicate-output','false-completion','unreported-new','old-contract','no-final-check')){
    $script:childCalls=0;$threw=$false;$dir=Join-Path $work $script:mode
    try{& $runner -AccessReportPath (Join-Path $work 'input.json') -OutputDirectory $dir}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'One compact report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$v=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No stderr in report'
    foreach($flag in @('databaseContacted','databaseWritesPerformed','realHbaRead','hbaChanged','firewallChanged','writerLoginAttempted','credentialsCreated','applicationWriterActivated','actionExecutionEnabled')){Check ($v.$flag -is [bool] -and -not $v.$flag) ('No side effect '+$flag)}
    if($script:mode -in @('pass','drift','two-replacements','all-missing')){
        Check (-not $threw -and $v.status -ceq 'PREPARATION_CAPTURED_STAGING_BLOCKED' -and $v.tests.status -ceq 'PASSED') 'Successful preparation'
        Check ($v.findings -contains 'CURRENT_FIREWALL_CANDIDATES_COLLECTED_NOT_APPROVED' -and $v.findings -contains 'NON_ATOMIC_FIREWALL_OBSERVATION') 'Collection not approval or atomic snapshot'
        if($script:mode -ceq 'two-replacements'){Check ($v.findings -contains 'SAVED_RULE_IDS_ABSENT_FROM_ENABLED_INBOUND_SET' -and $v.findings -contains 'CURRENT_CANDIDATES_NOT_IN_SAVED_BASELINE') 'Missing and unbaselined findings survive parent'}
        if($script:mode -ceq 'drift'){Check ($v.findings -contains 'SAVED_RULE_METADATA_CHANGED') 'Drift finding propagated'}
    }else{Check ($threw -and $v.status -ceq 'FAILED' -and $v.failureCode) 'Failure report retained'}
    if($script:mode -in @('dirty','bad-evidence')){Check ($script:childCalls -eq 0) 'Preflight stops child'}
    if($script:mode -ceq 'timeout'){Check ($v.firewallScope.inspectedRuleCount -eq 20) 'Timeout retains last full checkpoint'}
    if($script:mode -ceq 'provider-error'){Check ($v.firewallScope.diagnostic.errorId -match '^CimJob_ProviderFailure') 'Safe failure codes survive parent report'}
    Remove-Item -LiteralPath $files[0].FullName;[IO.Directory]::Delete($dir,$false)
}
[IO.Directory]::Delete($work,$false)
foreach($name in @('GetPaperWriterRestrictionPreparation.ps1','PaperWriterRestriction.ps1','PaperWriterFirewallScope.ps1','TestPaperWriterRestrictionWorkflow.ps1','TestPaperWriterRestrictionRunner.ps1')){
    $file=Join-Path $PSScriptRoot $name;$tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) ('Parses '+$name)
}
foreach($name in @('GetPaperWriterRestrictionPreparation.ps1','PaperWriterRestriction.ps1','PaperWriterFirewallScope.ps1')){
    $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw
    Check ($text -notmatch 'Set-NetFirewall|New-NetFirewall|Remove-NetFirewall|ALTER ROLE|Invoke-RestMethod|Invoke-PaperInstallerPsql|docker\s+(restart|stop|compose)|Remove-Item.*-Recurse') ('No activation '+$name)
}
Write-Host "PASS: $script:checks restriction runner/selector assertions; all runtime I/O mocked."
