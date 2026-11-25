#Requires -Version 7.0
[CmdletBinding()]
param([string]$OutputDirectory='C:\MarketBrainData\Review',[ValidatePattern('^[a-z][a-z0-9_]{0,62}$')][string]$Schema='public',
      [ValidateRange(60,1800)][int]$BuildTimeoutSeconds=1800,[switch]$Publisher)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$id=[guid]::NewGuid().ToString('N');$project='mb-writer-preflight-'+$id;$docker=$null;$runAttempted=$false
$priorSchema=$env:MARKETBRAIN_PREFLIGHT_SCHEMA
$priorKind=$env:MARKETBRAIN_PREFLIGHT_KIND
$watch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version='PAPER_WRITER_PREFLIGHT_BUNDLE_V1';status='RUNNING';runId=$id;updatedAtUtc=$null;elapsedSeconds=0;revision=$null;manifest=@{};events=@();steps=@();catalog=$null;failure=$null;cleanup=$null;schema=$Schema;configurationSource='Repository .env and existing process overrides; running-service target identity not verified';applicationRestartRequested=$false;databaseWritesRequested=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report.failureCode=$null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-writer-preflight-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($Publisher){$report.version='PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1';$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-publisher-preflight-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))}
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe or existing evidence path.'}
function Save { $report.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact }
function Stage([int]$Percent,[string]$Message) {
    $report.events+=@{percent=$Percent;message=$Message;atUtc=[DateTime]::UtcNow.ToString('o')};Save
    Write-Progress -Activity 'Paper writer application catalog preflight' -Status $Message -PercentComplete $Percent;Write-Host "[$Percent%] $Message"
}
function Compose([string]$Name,[string[]]$Arguments,[int]$Limit) {
    $argsList=@('compose','--project-name',$project,'--env-file',(Join-Path $repo '.env'),'-f',(Join-Path $repo 'compose.paper-writer-preflight.yaml'))+$Arguments
    $r=Invoke-PaperCatalogProcess $docker $argsList $repo $Limit
    # Never serialize Compose-expanded environment, stderr or raw command output: it could contain credentials.
    $report.steps+=@{stage=$Name;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;stdoutCharacters=$r.stdout.Length;stderrCharacters=$r.stderr.Length};Save
    return $r
}
function Prerequisite([string]$Name,[string[]]$Arguments,[int]$Limit) {
    $r=Invoke-PaperCatalogProcess $docker $Arguments $repo $Limit
    $report.steps+=@{stage=$Name;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;stdoutCharacters=$r.stdout.Length;stderrCharacters=$r.stderr.Length};Save
    if($r.timedOut){$report.failureCode=$Name.ToUpperInvariant().Replace('-','_')+'_TIMEOUT';throw 'Docker prerequisite timed out.'}
    if($r.exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.stdout)){$report.failureCode=$Name.ToUpperInvariant().Replace('-','_')+'_UNAVAILABLE';throw 'Docker prerequisite unavailable.'}
}
try {
    Stage 0 'Read-only catalog inspection. No application restart, account mutation, provider or model call.'
    if($Schema.StartsWith('pg_') -or $Schema -ceq 'information_schema'){throw 'Unsupported schema.'}
    if(-not (Test-Path -LiteralPath (Join-Path $repo '.env') -PathType Leaf)){throw 'Existing repository .env is required. Do not share it.'}
    $git=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'rev-parse','HEAD') $repo 10
    if($git.exitCode -ne 0 -or $git.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Cannot identify revision.'};$report.revision=$git.stdout.Trim()
    $dirty=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'status','--porcelain') $repo 10
    if($dirty.exitCode -ne 0 -or $dirty.stdout.Trim()){throw 'Preserve and review local changes before this run.'}
    foreach($file in @('compose.paper-writer-preflight.yaml','marketbrain-service/Dockerfile.paper-writer-preflight','marketbrain-service/pom.xml','marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterPreflight.java','ops/windows/PaperWriterPreflight.ps1','ops/windows/GetPaperWriterPreflight.ps1','ops/windows/NumericalHistoryEvidence.ps1')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
    $dockerCommands=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)
    $docker=[string]$dockerCommands[0].Source
    if(-not [IO.Path]::IsPathRooted($docker) -or -not (Test-Path -LiteralPath $docker -PathType Leaf)){throw 'Docker executable unavailable.'}
    $env:MARKETBRAIN_PREFLIGHT_SCHEMA=$Schema
    $env:MARKETBRAIN_PREFLIGHT_KIND=if($Publisher){'PUBLISHER'}else{'WRITER'}
    Stage 5 'Checking Docker engine and Compose plugin independently before configuration.'
    Prerequisite 'docker-engine' @('version','--format','{{.Server.Version}}') 60
    Prerequisite 'compose-plugin' @('compose','version','--short') 60
    Stage 10 'Checking standalone Compose configuration without printing credentials.'
    $r=Compose 'configuration' @('config','--quiet') 90
    if($r.exitCode -ne 0 -or $r.timedOut){$report.failureCode=if($r.timedOut){'COMPOSE_CONFIGURATION_TIMEOUT'}else{'COMPOSE_CONFIGURATION_REJECTED'};throw 'Compose configuration failed. Review .env locally; do not share credentials.'}
    Stage 20 'Building the standalone inspector; existing MarketBrain containers remain untouched.'
    $r=Compose 'inspector-build' @('build','paper-writer-preflight') $BuildTimeoutSeconds
    if($r.exitCode -ne 0 -or $r.timedOut){throw 'Inspector build failed. Stage/exit/timing saved; sensitive raw output deliberately withheld.'}
    Stage 65 'Inspecting PostgreSQL catalogs with read-only transaction, query deadlines and bounded results.'
    $runAttempted=$true
    $r=Compose 'catalog-read' @('run','--rm','--no-deps','-T','paper-writer-preflight') 180
    # Only the Java JSON contract is retained. Reject arbitrary native stdout rather than embedding it.
    if($r.stdout.Length -gt 100000 -or $r.timedOut){throw 'Inspector deadline/output limit exceeded.'}
    $parsed=$r.stdout|ConvertFrom-Json
    $expectedVersion=if($Publisher){'PAPER_PUBLISHER_PREFLIGHT_V1'}else{'PAPER_WRITER_PREFLIGHT_V1'}
    if($parsed.version -cne $expectedVersion){throw 'Unexpected inspector output.'}
    if($r.exitCode -ne 0 -or $parsed.status -cne 'CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED') {
        $report.failure='Inspector stopped; no automatic retry.'
        $report.catalog=@{status='STOPPED_REVIEW_REQUIRED';failureType=[string]$parsed.failureType;sqlState=[string]$parsed.sqlState}
        throw 'Catalog inspection stopped. Sanitized exception type and SQLSTATE saved where available.'
    }
    Assert-PaperWriterCatalog $parsed $Schema -Publisher:$Publisher
    $report.catalog=$parsed;$report.status='CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED'
    Stage 95 ('Catalog report captured; {0} installation findings require review. No roles or application settings changed.' -f @($parsed.installationBlockers).Count)
} catch {
    $report.status='STOPPED_REVIEW_REQUIRED'
    # Avoid serializing exceptions that can contain expanded environment values.
    $report.failure='Stopped during '+[string]$report.events[-1].message+' See stage exit codes and sanitized catalog failure, if available.'
    Write-Warning 'Preflight stopped; share the single report. No automatic retry or permission change.'
    if($report.failureCode){Write-Warning ('Failure code: '+$report.failureCode)}
} finally {
    if($runAttempted -and $docker) {
        try {
            $r=Compose 'owned-inspector-cleanup' @('down','--timeout','5') 30
            $report.cleanup=@{project=$project;exitCode=$r.exitCode;timedOut=$r.timedOut}
            if($r.exitCode -ne 0 -or $r.timedOut){$report.status='STOPPED_CLEANUP_REVIEW_REQUIRED';Write-Warning 'Standalone inspector cleanup incomplete; do not prune unrelated resources.'}
        } catch {$report.cleanup=@{project=$project;status='CLEANUP_REVIEW_REQUIRED'};$report.status='STOPPED_CLEANUP_REVIEW_REQUIRED'}
    }
    $env:MARKETBRAIN_PREFLIGHT_SCHEMA=$priorSchema
    $env:MARKETBRAIN_PREFLIGHT_KIND=$priorKind
    Stage 100 $report.status
    Write-Progress -Activity 'Paper writer application catalog preflight' -Completed
    Write-Host "Share this ONE file: $path"
}
if($report.status -cne 'CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED'){throw 'Preflight not complete; inspect the saved report before retrying.'}
