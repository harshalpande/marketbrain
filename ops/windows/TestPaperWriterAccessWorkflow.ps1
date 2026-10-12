# Offline contracts and mocked firewall queries; no local application, Docker or DB runtime.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterConnectionReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
$script:checks=0
function Check($Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Body){$failed=$false;try{$null=& $Body}catch{$failed=$true};Check $failed 'Expected rejection'}
function Route {@{version='PAPER_APPLICATION_ROUTE_V1';status='READ_ONLY_APPLICATION_ROUTE_OBSERVED';database='marketbrain';databaseOid='123';serverPort=5432;serverStartEpoch='123456.123456';applicationName=('mb-route-'+('a'*32));applicationUser='app';sessionUser='app';clientAddress='127.0.0.1';serverAddress='127.0.0.1';readOnly=$true;databaseWritesPerformed=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false}|ConvertTo-Json|ConvertFrom-Json}
$inventory=@{database='marketbrain';databaseOid='123';serverPort=5432;hbaRules=@(@{type='host';address='127.0.0.1';netmask='255.255.255.255';authMethod='scram-sha-256';optionsPresent=$false;hasError=$false})}
$server=@{serverStartEpoch='123456.123456'}
Assert-PaperApplicationRoute (Route) $inventory $server ('a'*32);Check $true 'Matched instance/session'
foreach($field in @('version','status','database','databaseOid','serverStartEpoch','applicationName','applicationUser','sessionUser','clientAddress','serverAddress')){$r=Route;$r.$field='wrong';Reject {Assert-PaperApplicationRoute $r $inventory $server ('a'*32)}}
foreach($port in @('5432',[double]5432,5433,$null)){$r=Route;$r.serverPort=$port;Reject {Assert-PaperApplicationRoute $r $inventory $server ('a'*32)}}
foreach($field in @('databaseWritesPerformed','writerLoginAttempted','actionExecutionEnabled')){foreach($value in @($true,'false',$null)){$r=Route;$r.$field=$value;Reject {Assert-PaperApplicationRoute $r $inventory $server ('a'*32)}}}
foreach($value in @($false,'true',$null)){$r=Route;$r.readOnly=$value;Reject {Assert-PaperApplicationRoute $r $inventory $server ('a'*32)}}
$fw=@{status='METADATA_CAPTURED_REVIEW_REQUIRED';truncated=$false;profiles=@(@{Enabled='True';DefaultInboundAction='Block'})*3;rules=@()}
Check (@(Get-PaperAccessFindings $inventory $fw (Route)).Count -eq 1) 'Even narrow evidence retains credential restriction gate'
$fw.rules=@(@{action='Allow'});Check ((Get-PaperAccessFindings $inventory $fw (Route)) -contains 'POSTGRES_PORT_CANDIDATE_ALLOW_RULES_REQUIRE_SCOPE_REVIEW') 'Allow not treated as effective reachability'
$fw.profiles[0].Enabled='False';Check ((Get-PaperAccessFindings $inventory $fw (Route)) -contains 'FIREWALL_PROFILE_REQUIRES_REVIEW') 'Disabled firewall visible'
$inventory.hbaRules[0].address='0.0.0.0';Check ((Get-PaperAccessFindings $inventory $fw (Route)) -contains 'NON_LOOPBACK_OR_COMPLEX_HBA_ALLOW_REQUIRES_REVIEW') 'Broad HBA visible'
$inventory.hbaRules[0].authMethod='trust';Check ((Get-PaperAccessFindings $inventory $fw (Route)) -contains 'NON_SCRAM_AUTHENTICATION_REQUIRES_REVIEW') 'Trust visible'
function Foundation {@{version='PAPER_WRITER_FOUNDATION_V1';status='FOUNDATION_CAPTURED_PRIVATE_BOUNDARY_REVIEW_REQUIRED';failureCode=$null;checkCount=15;checks=@(1..15);privateBoundary=@{status='OBSERVATIONS_CAPTURED_REVIEW_REQUIRED';failureCode=$null};databaseContacted=$false;databaseWritesPerformed=$false;realCredentialsCreated=$false;hbaChanged=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}|ConvertTo-Json -Depth 5|ConvertFrom-Json}
Assert-PaperFoundationEvidence (Foundation);Check $true 'Saved foundation accepted'
foreach($field in @('databaseContacted','databaseWritesPerformed','realCredentialsCreated','hbaChanged','applicationWriterActivated','actionExecutionEnabled')){$v=Foundation;$v.$field=$true;Reject {Assert-PaperFoundationEvidence $v}}
$v=Foundation;$v.checks=@('same')*15;Reject {Assert-PaperFoundationEvidence $v}

# Firewall child is executed against mocks, including port ranges, Any and unknown selectors.
$source=Get-Content (Join-Path $PSScriptRoot 'PaperWriterFirewallSnapshot.ps1') -Raw
$definition=$source.Substring(0,$source.IndexOf('$report=')).Replace('#Requires -Version 7.0','')
. ([scriptblock]::Create($definition))
foreach($port in @('5432','Any','5000-6000','RPC')){Check (Test-PortRelevant @{Protocol='TCP';LocalPort=$port}) 'Relevant or unknown port retained'}
foreach($port in @('80','5433','5000-5431')){Check (-not (Test-PortRelevant @{Protocol='TCP';LocalPort=$port})) 'Unrelated port excluded'}
Check (-not (Test-PortRelevant @{Protocol='UDP';LocalPort='5432'})) 'UDP irrelevant to PostgreSQL TCP'
$mocked=$source.Replace('#Requires -Version 7.0','').Replace("if(`$report.status -ceq 'FAILED'){exit 2}",'')
$mocked=$mocked.Replace('$watch.Elapsed.TotalSeconds -ge 180',"(`$script:case -ceq 'deadline' -and `$rows.Count -ge 2)")
function Get-NetFirewallProfile {param($PolicyStore);@('Domain','Private','Public')|ForEach-Object {[pscustomobject]@{Name=$_;Enabled='True';DefaultInboundAction='Block'}}}
function Get-NetFirewallPortFilter {param($AssociatedNetFirewallRule);$script:ports++;if($script:case -ceq 'throw' -and $AssociatedNetFirewallRule.Ordinal -eq 3){throw 'SECRET_NEVER_OUTPUT'};if($script:case -ceq 'missing'){return};$port=if($script:case -ceq 'irrelevant'){'80'}else{'Any'};[pscustomobject]@{Protocol='TCP';LocalPort=$port;RemotePort='Any'}}
function Get-NetFirewallRule {
    param($PolicyStore,$Enabled,$Direction)
    $script:ruleQueries++;if($PolicyStore -cne 'ActiveStore' -or $Enabled -cne 'True' -or $Direction -cne 'Inbound'){throw 'Server filter missing'}
    $n=switch($script:case){'101'{101};'500'{500};'1000'{1000};'limit'{1001};'inbound-limit'{2001};default{3}}
    1..$n|ForEach-Object {[pscustomobject]@{Name=if($script:case -ceq 'duplicate'){'same'}else{"fixture-$_"};Ordinal=$_;Enabled='True';Direction='Inbound';Action='Allow';Profile='Private';EdgeTraversalPolicy='Block';PolicyStoreSourceType='Local'}}
}
function Get-NetFirewallAddressFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{LocalAddress='Any';RemoteAddress='LocalSubnet'}}
function Get-NetFirewallApplicationFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Program=if($script:case -ceq 'payload' -and $AssociatedNetFirewallRule.Ordinal -eq 3){'x'*1000001}else{'C:\fixture\postgres.exe'}}}
function Get-NetFirewallServiceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Service='Any'}}
foreach($script:case in @('pass','101','500','1000','limit','inbound-limit','throw','deadline','payload','missing','duplicate','irrelevant')){
    $script:ports=0;$script:ruleQueries=0
    $text=(& ([scriptblock]::Create($mocked))) -join "`n";$r=Read-PaperFirewallOutput $text $false
    Check ($text -notmatch 'SECRET_NEVER_OUTPUT') 'No raw errors'
    Check (-not $r.configurationChanged -and -not $r.effectiveAccessProven) 'Metadata not access certification'
    Check ($script:ruleQueries -eq 1) 'Only one filtered rule enumeration'
    Check ($script:ports -le $r.inboundRuleCount) 'No per-port reverse rule lookups'
    if($script:case -in @('pass','101','500','1000','irrelevant')){
        Check ($r.status -ceq 'METADATA_CAPTURED_REVIEW_REQUIRED' -and -not $r.truncated) 'Complete relevant rules captured'
        $expected=if($script:case -ceq 'irrelevant'){0}elseif($script:case -ceq 'pass'){3}else{[int]$script:case}
        Check ($r.rules.Count -eq $expected -and $r.scannedRuleCount -eq $r.inboundRuleCount) 'All candidate rows and counts retained'
    }else{Check ($r.status -ceq 'FAILED' -and $r.truncated) 'Limits and exceptions stop with incomplete evidence'}
    if($script:case -in @('throw','deadline','payload')){Check ($r.rules.Count -eq 2 -and $r.profiles.Count -eq 3) 'Partial rows and profiles preserved'}
    if($script:case -ceq 'limit'){Check ($r.failureCode -ceq 'FIREWALL_RULE_LIMIT' -and $r.rules.Count -eq 1000) 'Rule overflow retains first 1000, never success'}
    if($script:case -ceq 'inbound-limit'){Check ($r.failureCode -ceq 'FIREWALL_INBOUND_RULE_LIMIT' -and $script:ports -eq 0) 'Enumeration overflow stops before per-rule work'}
    if($script:case -ceq '500'){$checkpoint=($text -split '\r?\n')[1];$partial=Read-PaperFirewallOutput ($checkpoint+"`n{" ) $true;Check ($partial.rules.Count -eq 100 -and $partial.status -ceq 'FAILED' -and $partial.truncated) 'Hard timeout retains last complete JSON line'}
    if($script:case -ceq 'pass'){$valid=$text}
}
$v=Read-PaperFirewallOutput $valid $false;$v|Add-Member -NotePropertyName unexpectedSecret -NotePropertyValue 'SECRET_NEVER_OUTPUT'
$raw=$v|ConvertTo-Json -Depth 8 -Compress;$v=Read-PaperFirewallOutput $raw $false
Check (($v|ConvertTo-Json -Depth 8) -notmatch 'SECRET_NEVER_OUTPUT') 'Unexpected fields discarded'
$v.scannedRuleCount=0;Reject {Read-PaperFirewallOutput ($v|ConvertTo-Json -Depth 8 -Compress) $false}
Reject {Read-PaperFirewallOutput '{' $false}
Reject {Read-PaperFirewallOutput ('x'*(32MB+1)) $false}
foreach($file in @('GetPaperWriterAccessReview.ps1','PaperWriterAccessReview.ps1','PaperWriterFirewallSnapshot.ps1')){
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'Parses'
}
$runner=Get-Content (Join-Path $PSScriptRoot 'GetPaperWriterAccessReview.ps1') -Raw
Check ($runner -notmatch 'docker\s+(restart|stop|compose up)|ALTER ROLE|Set-NetFirewall|New-NetFirewall|Remove-NetFirewall|--env') 'No activation or credentials in Docker arguments'
Check ($runner.Contains("'/tmp/mb-route-'+`$id") -and $runner -notmatch 'rm.*-rf|Remove-Item.*-Recurse') 'Exact nonrecursive diagnostic cleanup'
Write-Host "PASS: $script:checks access-review assertions; all native activity mocked."
