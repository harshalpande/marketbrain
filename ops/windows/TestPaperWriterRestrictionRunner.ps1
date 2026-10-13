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
    return [scriptblock]::Create($text)
}
$child=Get-OfflineScript 'PaperWriterFirewallScope.ps1';$runner=Get-OfflineScript 'GetPaperWriterRestrictionPreparation.ps1'
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
function Get-NetFirewallRule {param($PolicyStore,$Name)
    $script:queries++;if($script:mode -ceq 'query-fail' -and $script:queries -eq 22){throw 'SECRET_SENTINEL'}
    if($script:mode -ceq 'missing-rule'){return}
    $v=[pscustomobject]@{Name=$Name;Action='Allow';Profile='Any';Enabled='True';Direction='Inbound';EdgeTraversalPolicy='Block';PolicyStoreSourceType='Local'}
    if($script:mode -ceq 'drift'){$v.Enabled='False'}
    $v;if($script:mode -ceq 'ambiguous'){$v}
}
function Get-NetFirewallPortFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Protocol='TCP';LocalPort=@('Any');RemotePort=@('Any')}}
function Get-NetFirewallAddressFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{LocalAddress=@('Any');RemoteAddress=@('Any')}}
function Get-NetFirewallApplicationFilter {param($AssociatedNetFirewallRule);if($script:mode -ceq 'missing-package'){[pscustomobject]@{Program='Any'}}else{[pscustomobject]@{Program='Any';Package='test-package'}}}
function Get-NetFirewallServiceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Service='Any'}}
function Get-NetFirewallInterfaceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{InterfaceAlias=@('Any')}}
function Get-NetFirewallInterfaceTypeFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{InterfaceType=@('Any')}}
function Get-NetFirewallSecurityFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Authentication='NotRequired';Encryption='NotRequired';OverrideBlockRules=$false;LocalUser='Any';RemoteUser='Any';RemoteMachine='Any'}}
$normal=@(1..126|ForEach-Object {[pscustomobject]@{name=('rule-'+$_);action='Allow';profile='Any';protocol='TCP';localPort=@('Any');remotePort=@('Any');localAddress=@('Any');remoteAddress=@('Any');program='Any';service='Any';edgeTraversal='Block';policySourceType='Local'}})
foreach($script:mode in @('pass','drift','missing-rule','ambiguous','query-fail','missing-package','no-listener','unsafe-name','limit')){
    $script:saved.firewall.rules=$normal;$script:queries=0
    if($script:mode -ceq 'unsafe-name'){$script:saved.firewall.rules=@([pscustomobject]@{name='*'})}
    if($script:mode -ceq 'limit'){$script:saved.firewall.rules=$normal+$normal}
    $lines=@(& $child -AccessReportPath 'unused' -ExpectedHash 'FFFF18099697737091CB1A8B031AA5ED8F6ACE4C9567DECA6F54C60A11962650')
    $raw=$lines -join "`n";$v=$lines[-1]|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No process command line or raw error retained'
    Check (-not $v.configurationChanged -and -not $v.effectiveAccessProven -and -not $v.newRulesAssessed) 'No access assertion'
    if($script:mode -in @('pass','drift','missing-package')){
        Check ($v.status -ceq 'SELECTORS_CAPTURED_REVIEW_REQUIRED' -and $v.inspectedRuleCount -eq 126 -and -not $v.truncated) 'Complete bounded selector collection'
        Check ($v.ruleDriftDetected -eq ($script:mode -ceq 'drift')) 'Drift reported'
        if($script:mode -ceq 'pass'){
            Check ($v.rules[0].package -ceq 'test-package' -and $v.rules[0].program -ceq 'Any') 'Package not confused with program'
            Check ($v.rules[0].interfaceAlias[0] -ceq 'Any' -and $v.rules[0].security.Authentication -ceq 'NotRequired') 'Missing selectors now retained'
            Check ($v.listeners.Count -eq 1 -and $v.listenerProcesses.Count -eq 1 -and $v.activeProfiles.Count -eq 1) 'Listener/profile metadata captured'
            $script:successJson=$lines[-1]
            $script:partialJson=$lines[1]
        }
        if($script:mode -ceq 'missing-package'){Check ($v.rules[0].missingSelectorFields -contains 'Package') 'Unknown selector explicit'}
    }else{
        Check ($v.status -ceq 'FAILED' -and $v.truncated -and $v.failureCode) 'Failure not success'
        if($script:mode -ceq 'query-fail'){Check ($v.rules.Count -eq 21 -and $v.failureCode -ceq 'SCOPE_QUERY_FAILED') 'Partial checkpoints retained'}
    }
}
function git {$global:LASTEXITCODE=0;if($args -contains 'status' -and $script:mode -ceq 'dirty'){' M own.txt'};if($args -contains 'rev-parse'){'a'*40}}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
    $script:childCalls++;Check ($LimitSeconds -eq 180 -and $Arguments -contains '-NonInteractive') 'Bounded noninteractive child'
    $stdout=$script:successJson;$exit=0;$timedOut=$false
    switch($script:mode){
        'timeout' {$stdout=$script:partialJson+"`n{";$exit=-999;$timedOut=$true}
        'malformed' {$stdout=$script:successJson+"`nnot-json"}
        'failed-child' {$exit=2}
        'bad-count' {$v=$stdout|ConvertFrom-Json;$v.inspectedRuleCount=0;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
        'drift' {$v=$stdout|ConvertFrom-Json;$v.ruleDriftDetected=$true;$stdout=$v|ConvertTo-Json -Depth 12 -Compress}
    }
    [pscustomobject]@{stdout=$stdout;stderr='SECRET_SENTINEL';exitCode=$exit;timedOut=$timedOut;elapsedSeconds=0.01}
}
$script:saved.firewall.rules=$normal
foreach($script:mode in @('pass','drift','dirty','bad-evidence','timeout','malformed','failed-child','bad-count')){
    $script:childCalls=0;$threw=$false;$dir=Join-Path $work $script:mode
    try{& $runner -AccessReportPath (Join-Path $work 'input.json') -OutputDirectory $dir}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'One compact report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$v=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No stderr in report'
    foreach($flag in @('databaseContacted','databaseWritesPerformed','realHbaRead','hbaChanged','firewallChanged','writerLoginAttempted','credentialsCreated','applicationWriterActivated','actionExecutionEnabled')){Check ($v.$flag -is [bool] -and -not $v.$flag) ('No side effect '+$flag)}
    if($script:mode -in @('pass','drift')){
        Check (-not $threw -and $v.status -ceq 'PREPARATION_CAPTURED_STAGING_BLOCKED' -and $v.tests.status -ceq 'PASSED') 'Successful preparation'
        Check ($v.findings -contains 'NEW_FIREWALL_RULES_SINCE_SNAPSHOT_NOT_ASSESSED') 'Snapshot limitation explicit'
        if($script:mode -ceq 'drift'){Check ($v.findings -contains 'SAVED_RULE_METADATA_CHANGED') 'Drift finding propagated'}
    }else{Check ($threw -and $v.status -ceq 'FAILED' -and $v.failureCode) 'Failure report retained'}
    if($script:mode -in @('dirty','bad-evidence')){Check ($script:childCalls -eq 0) 'Preflight stops child'}
    if($script:mode -ceq 'timeout'){Check ($v.firewallScope.inspectedRuleCount -eq 20) 'Timeout retains last full checkpoint'}
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
