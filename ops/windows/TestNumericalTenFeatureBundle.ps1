#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Auto','Java','Docker')][string]$Runtime='Auto',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [ValidateRange(10,300)][int]$TimeoutSeconds=120,
    [string]$ResumeReport
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew()
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'marketbrain-service\src\main\java\in\marketbrain\training\NumericalTenFeatureEngineering.java'
$id=[guid]::NewGuid().ToString('N');$containerName='marketbrain-ten-feature-'+$id
$image='maven:3.9.11-eclipse-temurin-21';$docker=$null;$started=$false
$report=[ordered]@{version='NUMERICAL_TEN_FEATURE_BUNDLE_V1';status='RUNNING';runId=$id;createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null
    elapsedSeconds=0;powerShellVersion=$PSVersionTable.PSVersion.ToString();manifest=$null;runtime=$null;runtimeProbe=$null;process=$null
    javaResult=$null;javaResultTextSha256=$null;cleanup=$null;failure=$null;previousReportSha256=$null;executionMode='FIXED_SYNTHETIC_SUITE';events=@()}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-ten-feature-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($path.Length+41 -ge 260){throw 'Choose a shorter output directory for atomic evidence checkpoints.'}
if(Test-Path -LiteralPath $path){throw 'Refusing to overwrite existing evidence.'}
function Update-TenFeatureProgress([int]$Percent,[string]$Detail) {
    Write-Host "[$Percent%] $Detail"
    Write-Progress -Activity 'Ten-feature numerical engineering' -Status $Detail -PercentComplete $Percent
    $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;detail=$Detail})
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
}
try {
    Update-TenFeatureProgress 0 'Preparing fixed synthetic tests; no service, database, market data or LLM.'
    $revision=Invoke-EvaluationProcess 'git' @('-C',$root,'rev-parse','HEAD') 10
    if($revision.exitCode -ne 0 -or $revision.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Cannot identify repository revision.'}
    $manifest=[ordered]@{codeRevision=$revision.stdout.Trim()}
    $files=[ordered]@{source=$source;runner=$PSCommandPath;reviewer=(Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1');processHelper=(Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1');checkpointHelper=(Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1');contract=(Join-Path $root 'ops\data\numerical-prefit-contract-v1.json')}
    foreach($key in $files.Keys){$manifest[$key]=(Get-FileHash -LiteralPath $files[$key] -Algorithm SHA256).Hash}
    $report.manifest=$manifest
    $contractText=[IO.File]::ReadAllText($files.contract).Replace("`r`n","`n")
    if((Get-TenFeatureTextHash $contractText) -cne '0ca5efab05b6fde03c16adb4181e31d63893e80fee8b71a63087eb35385a69d6'){throw 'Contract changed; engineering review required.'}
    if($ResumeReport) {
        $item=Get-Item -LiteralPath $ResumeReport
        if($item.Length -gt 8MB){throw 'Resume evidence exceeds 8 MiB bound.'}
        $saved=Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
        if($saved.version -cne $report.version){throw 'Wrong resume report.'}
        foreach($key in $manifest.Keys){if($saved.manifest.$key -cne $manifest[$key]){throw "Resume identity mismatch: $key"}}
        if($null -eq $saved.javaResult -or $null -eq $saved.process -or $saved.process.exitCode -ne 0 -or $saved.process.timedOut){throw 'No completed JVM result to reuse. Preserve this report and rerun the short synthetic suite without ResumeReport.'}
        if((Get-TenFeatureTextHash $saved.process.stdout) -cne $saved.javaResultTextSha256){throw 'Saved process output checksum mismatch.'}
        $report.previousReportSha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        $report.executionMode='OFFLINE_SAVED_RESULT_REVIEW';$report.process=$saved.process
        $report.javaResult=$saved.process.stdout | ConvertFrom-Json;$report.javaResultTextSha256=$saved.javaResultTextSha256
        Update-TenFeatureProgress 85 'Rechecking saved synthetic result; no new JVM execution.'
    } else {
        $java=Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $javac=Get-Command javac -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if($Runtime -eq 'Auto'){$Runtime=if($java -and $javac){'Java'}else{'Docker'}};$report.runtime=$Runtime
        Update-TenFeatureProgress 15 "Resolving $Runtime runtime. No application restart or image build."
        if($Runtime -eq 'Java') {
            if(-not $java -or -not $javac){throw 'JDK 21+ required; alternatively use cached Docker JDK.'}
            $executable=$java.Source;$arguments=@('-Xmx256m','--source','21',$source,'--synthetic-suite',$manifest.codeRevision)
        } else {
            $docker=Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1
            $report.runtimeProbe=Invoke-EvaluationProcess $docker.Source @('image','inspect',$image,'--format','{{.Id}}') 15
            if($report.runtimeProbe.exitCode -ne 0){throw "Cached JDK image missing. Install JDK 21+ or explicitly pull $image. No automatic download."}
            if($source.Contains(',')){throw 'Docker bind path cannot contain commas.'}
            $executable=$docker.Source
            $arguments=@('run','--rm','--pull','never','--name',$containerName,'--network','none','--read-only','--cap-drop','ALL',
                '--security-opt','no-new-privileges','--pids-limit','128','--memory','768m','--cpus','1','--tmpfs','/tmp:rw,nosuid,size=128m',
                '--workdir','/tmp','--mount',"type=bind,source=$source,target=/input/NumericalTenFeatureEngineering.java,readonly",'--entrypoint','java',
                $image,'-Xmx256m','--source','21','/input/NumericalTenFeatureEngineering.java','--synthetic-suite',$manifest.codeRevision)
            $started=$true
        }
        Update-TenFeatureProgress 40 'Running numerical, leakage, adverse-scenario and model-reload checks.'
        $report.process=Invoke-EvaluationProcess $executable $arguments $TimeoutSeconds
        $report.javaResultTextSha256=Get-TenFeatureTextHash $report.process.stdout
        # Preserve stdout/stderr before parse/review, including failed JVM suites.
        Save-NumericalHistoryReport $report $path -Compact
        if($report.process.stdout){try{$report.javaResult=$report.process.stdout | ConvertFrom-Json}catch{}}
        if($report.process.timedOut -or $report.process.exitCode -ne 0){throw 'Synthetic JVM failed/timed out. Review embedded stdout/stderr; no automatic retry.'}
        Update-TenFeatureProgress 85 'Independently checking metrics, costs, coverage, identities and safety flags.'
    }
    Assert-TenFeatureBundle $report.javaResult
    foreach($fold in $report.javaResult.folds){if($fold.model.metadata.codeRevision -cne $manifest.codeRevision){throw 'Model code identity mismatch.'}}
    $report.status='SYNTHETIC_CHECKS_PASSED_MARKET_FIT_BLOCKED'
    Update-TenFeatureProgress 100 'Engineering verification passed. Market predictive quality is not measured.'
} catch {$report.status='FAILED';$report.failure=$_.Exception.Message}
finally {
    if($report.status -eq 'RUNNING'){$report.status='INTERRUPTED';$report.failure='Interrupted before completion.'}
    if($started -and $docker){try{$report.cleanup=Invoke-EvaluationProcess $docker.Source @('rm','--force',$containerName) 15}catch{$report.cleanup=[pscustomobject]@{error=$_.Exception.Message}}}
    $timer.Stop();$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact
    Write-Progress -Activity 'Ten-feature numerical engineering' -Completed
    Write-Progress -Activity 'Numerical evaluation engineering' -Completed
    Write-Host ('{0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this ONE file: $path"
}
if($report.status -ne 'SYNTHETIC_CHECKS_PASSED_MARKET_FIT_BLOCKED'){throw $report.failure}
