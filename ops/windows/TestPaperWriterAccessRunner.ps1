# Execute the real orchestration with native processes, administrator check and prompts mocked.
$ErrorActionPreference='Stop'
foreach($helper in @('NumericalHistoryEvidence.ps1','PaperWriterInstallation.ps1','PaperWriterConnectionReview.ps1','PaperWriterPreflight.ps1','PaperWriterCustody.ps1','PaperWriterAccessReview.ps1')){. (Join-Path $PSScriptRoot $helper)}
$script:checks=0
function Check($v,$label){if(-not $v){throw $label};$script:checks++}
foreach($fixtureSource in @('TestPaperWriterConnectionWorkflow.ps1','TestPaperWriterAccessWorkflow.ps1')){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $fixtureSource),[ref]$t,[ref]$e)
    foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Sample','Receipt','Installed','Inventory','Route','Foundation')},$true)){. ([scriptblock]::Create($f.Extent.Text))}
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$text=Get-Content (Join-Path $PSScriptRoot 'GetPaperWriterAccessReview.ps1') -Raw
$text=$text.Replace('#Requires -Version 7.0','')
$text=[regex]::Replace($text,'(?m)^\. \(Join-Path \$PSScriptRoot ''[^'']+''\)\r?\n','')
$text=$text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$text=[regex]::Replace($text,'(?m)^    \$principal=.*\r?\n','')
$text=[regex]::Replace($text,'(?m)^    if\(-not \$principal\.IsInRole.*\r?\n','')
$runner=[scriptblock]::Create($text)
$work=Join-Path $env:TEMP ('access-runner-offline-'+[Guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $work)
$installation=Join-Path $work 'install.json';$foundationPath=Join-Path $work 'foundation.json'
$v=Installed;$v|Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue $null;Save-NumericalHistoryReport $v $installation -Compact
$v=Foundation;$v|Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue $null;Save-NumericalHistoryReport $v $foundationPath -Compact
function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40};if($args -contains 'status' -and $script:case -ceq 'dirty'){' M own.txt'}}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=('C:\synthetic\'+$Name.TrimEnd('.exe')+'.exe')}}
function Test-Path {param($LiteralPath,$PathType);if($LiteralPath -like '*psql.exe'){return $true};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}}
function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){return (ConvertTo-SecureString 'SECRET_SENTINEL' -AsPlainText -Force)};if($Prompt -ceq 'Confirm database name'){if($script:case -ceq 'cancel'){return 'NO'};return 'marketbrain'};return 'postgres'}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
    $script:nativeCalls++;Check ($LimitSeconds -le 210) 'Bounded stage'
    $out='';$exit=0;$timeout=$false
    if($Arguments -contains 'PaperWriterFirewallSnapshot.ps1' -or ($Arguments -join ' ') -like '*PaperWriterFirewallSnapshot.ps1*'){
        $snapshot=@{version='PAPER_FIREWALL_SNAPSHOT_V2';status='METADATA_CAPTURED_REVIEW_REQUIRED';truncated=$false;failureCode=$null;elapsedSeconds=0.01;inboundRuleCount=0;scannedRuleCount=0;candidateRuleCount=0;configurationChanged=$false;effectiveAccessProven=$false;profiles=@(@{Enabled='True';DefaultInboundAction='Block'})*3;rules=@()}
        if($script:case -in @('firewall-fail','firewall-limit','firewall-timeout')){
            $exit=2;$snapshot.status='FAILED';$snapshot.truncated=$true;$snapshot.failureCode='FIREWALL_QUERY_FAILED'
            $snapshot.rules=@(@{name='preserved';action='Allow'});$snapshot.inboundRuleCount=101;$snapshot.scannedRuleCount=1;$snapshot.candidateRuleCount=1
            if($script:case -ceq 'firewall-limit'){$snapshot.failureCode='FIREWALL_RULE_LIMIT'}
            if($script:case -ceq 'firewall-timeout'){$snapshot.status='RUNNING';$snapshot.failureCode=$null;$timeout=$true}
        }
        $out=$snapshot|ConvertTo-Json -Depth 8 -Compress
        if($script:case -ceq 'firewall-timeout'){$out+="`n{"}
    }elseif($Arguments -contains '--release'){
        if($script:case -ceq 'compile-fail'){$exit=1}else{
            $destination=$Arguments[3];$dir=Join-Path $destination 'in\marketbrain\paper';[void][IO.Directory]::CreateDirectory($dir);[IO.File]::WriteAllText((Join-Path $dir 'PaperApplicationRouteProbe.class'),'synthetic')
        }
    }elseif($Arguments[0] -ceq 'ps'){$out='abcdef012345';if($script:case -ceq 'ambiguous'){$out+="`nabcdef012346"}}
    elseif($Arguments -contains 'java'){
        $script:probeId=$Arguments[-1];$v=Route;$v.applicationName='mb-route-'+$script:probeId
        if($script:case -ceq 'pass-inet-mask'){$v.clientAddress='127.0.0.1/32';$v.serverAddress='127.0.0.1/32'}
        if($script:case -ceq 'pass-ipv6'){$v.clientAddress='::1/128';$v.serverAddress='::1/128'}
        if($script:case -ceq 'invalid-address'){$v.clientAddress='127.0.0.1/24'}
        $out=$v|ConvertTo-Json -Compress
        if($script:case -ceq 'probe-fail'){$exit=2;$out='{"version":"PAPER_APPLICATION_ROUTE_V1","status":"FAILED","failureCode":"PROBE_CONNECTION_OR_QUERY_FAILED"}'}
        if($script:case -ceq 'probe-timeout'){$timeout=$true}
    }elseif($Arguments -contains 'rm' -and $script:case -ceq 'cleanup-fail'){$exit=1}
    return [pscustomobject]@{stdout=$out;stderr='SECRET_SENTINEL';exitCode=$exit;timedOut=$timeout;elapsedSeconds=0.01}
}
function Invoke-PaperInstallerPsql($Executable,$Database,$Port,$Admin,$Password,$Sql){
    $script:dbCalls++;Check ($Sql.Contains('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;') -and $Sql.EndsWith('ROLLBACK;')) 'Read-only SQL boundary'
    Check ($Sql -notmatch 'SECRET_SENTINEL|COMMIT;|ALTER ROLE|CREATE ROLE') 'No credential/activation SQL'
    $epoch=if($script:case -ceq 'instance-mismatch'){'999.123456'}else{'123456.123456'}
    $out=((Receipt 'Verify')|ConvertTo-Json -Compress)+"`n"+((Inventory)|ConvertTo-Json -Depth 10 -Compress)+"`n"+(@{serverStartEpoch=$epoch}|ConvertTo-Json -Compress)
    return [pscustomobject]@{stdout=$out;exitCode=if($script:case -ceq 'sql-fail'){3}else{0};timedOut=$false;elapsedSeconds=0.01;sqlStates=@();assertionFailures=@()}
}
foreach($script:case in @('pass','pass-inet-mask','pass-ipv6','invalid-address','dirty','firewall-fail','firewall-limit','firewall-timeout','compile-fail','ambiguous','probe-fail','probe-timeout','cancel','sql-fail','instance-mismatch','cleanup-fail')){
    $script:nativeCalls=0;$script:dbCalls=0;$dir=Join-Path $work $script:case;$threw=$false
    try{& $runner -InstallationReportPath $installation -FoundationReportPath $foundationPath -OutputDirectory $dir}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'Single compact report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No raw process errors or credentials'
    Check (-not $r.databaseWritesPerformed -and -not $r.applicationWriterActivated -and -not $r.writerLoginAttempted -and -not $r.configurationChanged) 'No side effects'
    Check ($script:dbCalls -le 1) 'No database retries'
    if($script:case -in @('pass','pass-inet-mask','pass-ipv6')){
        Check (-not $threw -and $r.status -ceq 'ACCESS_EVIDENCE_CAPTURED_REVIEW_REQUIRED' -and $r.diagnosticCleanupComplete -and $r.validationStage -ceq 'COMPLETE') 'Successful guarded workflow'
        Check ($r.findings -notcontains 'APPLICATION_SOURCE_NOT_LOOPBACK_REVIEW_EXACT_HBA_SCOPE') 'No false loopback finding'
    }else{Check ($threw -and $r.status -ceq 'FAILED' -and $r.failureCode) ('Failure retained: '+$script:case)}
    if($script:case -in @('invalid-address','instance-mismatch')){
        Check ($null -ne $r.inventory -and $null -ne $r.verification -and $null -ne $r.serverMetadata) 'Validated admin evidence retained after route validation failure'
        Check ($r.validationStage -ceq 'ROUTE_IDENTITY_AND_ADDRESS' -and -not $r.existingApplicationLoginProbed) 'Failed validation stage retained without accepting route'
    }
    if($script:case -ceq 'invalid-address'){Check ($r.failureCode -ceq 'ACCESS_ROUTE_ADDRESS_INVALID') 'CIDR subnet is not accepted as host'}
    if($script:case -eq 'firewall-fail'){Check ($r.diagnosticFailureCode -ceq 'FIREWALL_QUERY_FAILED') 'Safe firewall diagnostic'}
    if($script:case -in @('firewall-fail','firewall-limit','firewall-timeout')){
        Check ($r.firewall.rules.Count -eq 1 -and $r.firewall.truncated -and $r.firewall.profiles.Count -eq 3) 'Partial evidence survives runner failure'
        Check ($script:nativeCalls -eq 1 -and -not $r.existingApplicationLoginProbed) 'No compile or app login after incomplete firewall'
    }
    if($script:case -eq 'firewall-timeout'){Check ($r.diagnosticFailureCode -ceq 'FIREWALL_PROCESS_INTERRUPTED') 'Hard timeout is explicit'}
    if($script:case -eq 'probe-fail'){Check ($r.diagnosticFailureCode -ceq 'PROBE_CONNECTION_OR_QUERY_FAILED') 'Safe probe diagnostic'}
    if($script:case -in @('dirty','firewall-fail','firewall-limit','firewall-timeout','compile-fail','ambiguous','probe-fail','probe-timeout','cancel')){Check ($script:dbCalls -eq 0) 'Stops before admin database'}
}
Write-Host "PASS: $script:checks runner assertions; all runtime I/O mocked. Fixtures: $work"
