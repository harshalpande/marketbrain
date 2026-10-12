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
function Get-NetFirewallProfile {param($PolicyStore);@('Domain','Private','Public')|ForEach-Object {[pscustomobject]@{Name=$_;Enabled='True';DefaultInboundAction='Block'}}}
function Get-NetFirewallPortFilter {param($PolicyStore);if($script:case -ceq 'throw'){throw 'SECRET_NEVER_OUTPUT'};$n=if($script:case -ceq 'limit'){2001}else{1};1..$n|ForEach-Object {[pscustomobject]@{Protocol='TCP';LocalPort='5432';RemotePort='Any'}}}
function Get-NetFirewallRule {param($AssociatedNetFirewallPortFilter);[pscustomobject]@{Name='fixture';Enabled='True';Direction='Inbound';Action='Allow';Profile='Private';EdgeTraversalPolicy='Block';PolicyStoreSourceType='Local'}}
function Get-NetFirewallAddressFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{LocalAddress='Any';RemoteAddress='LocalSubnet'}}
function Get-NetFirewallApplicationFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Program='C:\fixture\postgres.exe'}}
function Get-NetFirewallServiceFilter {param($AssociatedNetFirewallRule);[pscustomobject]@{Service='Any'}}
foreach($script:case in @('pass','limit','throw')){
    $text=& ([scriptblock]::Create($mocked));$r=$text|ConvertFrom-Json
    Check ($text -notmatch 'SECRET_NEVER_OUTPUT') 'No raw errors'
    Check (-not $r.configurationChanged -and -not $r.effectiveAccessProven) 'Metadata not access certification'
    if($script:case -ceq 'pass'){Check ($r.status -ceq 'METADATA_CAPTURED_REVIEW_REQUIRED' -and $r.rules.Count -eq 1) 'Relevant rules captured'}else{Check ($r.status -ceq 'FAILED') 'Limits and exceptions stop'}
}
foreach($file in @('GetPaperWriterAccessReview.ps1','PaperWriterAccessReview.ps1','PaperWriterFirewallSnapshot.ps1')){
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'Parses'
}
$runner=Get-Content (Join-Path $PSScriptRoot 'GetPaperWriterAccessReview.ps1') -Raw
Check ($runner -notmatch 'docker\s+(restart|stop|compose up)|ALTER ROLE|Set-NetFirewall|New-NetFirewall|Remove-NetFirewall|--env') 'No activation or credentials in Docker arguments'
Check ($runner.Contains("'/tmp/mb-route-'+`$id") -and $runner -notmatch 'rm.*-rf|Remove-Item.*-Recurse') 'Exact nonrecursive diagnostic cleanup'
Write-Host "PASS: $script:checks access-review assertions; all native activity mocked."
