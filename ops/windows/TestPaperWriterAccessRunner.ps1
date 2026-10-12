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
    $script:nativeCalls++;Check ($LimitSeconds -le 90) 'Bounded stage'
    $out='';$exit=0;$timeout=$false
    if($Arguments -contains 'PaperWriterFirewallSnapshot.ps1' -or ($Arguments -join ' ') -like '*PaperWriterFirewallSnapshot.ps1*'){
        $out=@{version='PAPER_FIREWALL_SNAPSHOT_V1';status='METADATA_CAPTURED_REVIEW_REQUIRED';truncated=$false;configurationChanged=$false;profiles=@(@{Enabled='True';DefaultInboundAction='Block'})*3;rules=@()}|ConvertTo-Json -Depth 8 -Compress
        if($script:case -ceq 'firewall-fail'){$exit=2;$out='{"version":"PAPER_FIREWALL_SNAPSHOT_V1","status":"FAILED","failureCode":"FIREWALL_QUERY_FAILED"}'}
    }elseif($Arguments -contains '--release'){
        if($script:case -ceq 'compile-fail'){$exit=1}else{
            $destination=$Arguments[3];$dir=Join-Path $destination 'in\marketbrain\paper';[void][IO.Directory]::CreateDirectory($dir);[IO.File]::WriteAllText((Join-Path $dir 'PaperApplicationRouteProbe.class'),'synthetic')
        }
    }elseif($Arguments[0] -ceq 'ps'){$out='abcdef012345';if($script:case -ceq 'ambiguous'){$out+="`nabcdef012346"}}
    elseif($Arguments -contains 'java'){
        $script:probeId=$Arguments[-1];$v=Route;$v.applicationName='mb-route-'+$script:probeId;$out=$v|ConvertTo-Json -Compress
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
foreach($script:case in @('pass','dirty','firewall-fail','compile-fail','ambiguous','probe-fail','probe-timeout','cancel','sql-fail','instance-mismatch','cleanup-fail')){
    $script:nativeCalls=0;$script:dbCalls=0;$dir=Join-Path $work $script:case;$threw=$false
    try{& $runner -InstallationReportPath $installation -FoundationReportPath $foundationPath -OutputDirectory $dir}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'Single compact report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'SECRET_SENTINEL') 'No raw process errors or credentials'
    Check (-not $r.databaseWritesPerformed -and -not $r.applicationWriterActivated -and -not $r.writerLoginAttempted -and -not $r.configurationChanged) 'No side effects'
    Check ($script:dbCalls -le 1) 'No database retries'
    if($script:case -ceq 'pass'){Check (-not $threw -and $r.status -ceq 'ACCESS_EVIDENCE_CAPTURED_REVIEW_REQUIRED' -and $r.diagnosticCleanupComplete) 'Successful guarded workflow'}else{Check ($threw -and $r.status -ceq 'FAILED' -and $r.failureCode) ('Failure retained: '+$script:case)}
    if($script:case -eq 'firewall-fail'){Check ($r.diagnosticFailureCode -ceq 'FIREWALL_QUERY_FAILED') 'Safe firewall diagnostic'}
    if($script:case -eq 'probe-fail'){Check ($r.diagnosticFailureCode -ceq 'PROBE_CONNECTION_OR_QUERY_FAILED') 'Safe probe diagnostic'}
    if($script:case -in @('dirty','firewall-fail','compile-fail','ambiguous','probe-fail','probe-timeout','cancel')){Check ($script:dbCalls -eq 0) 'Stops before admin database'}
}
Write-Host "PASS: $script:checks runner assertions; all runtime I/O mocked. Fixtures: $work"
