#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Evaluation','Baselines')][string]$Suite='Evaluation',
    [ValidateSet('Auto','Java','Docker')][string]$Runtime='Auto',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [ValidateRange(5,300)][int]$TimeoutSeconds=120
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew()
$source=Join-Path $PSScriptRoot '..\..\marketbrain-service\src\main\java\in\marketbrain\training\NumericalEvaluationEngineering.java'
$id=[guid]::NewGuid().ToString('N')
$containerName='marketbrain-eval-'+$id
$image='maven:3.9.11-eclipse-temurin-21'
$baseline=$Suite -eq 'Baselines'
$cliArgument=if($baseline){'--synthetic-baselines'}else{'--synthetic-smoke'}
$prefix=if($baseline){'numerical-prediction-bundle'}else{'numerical-evaluation-smoke'}
$report=[ordered]@{version='NUMERICAL_EVALUATION_SMOKE_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o')
    updatedAtUtc=$null;elapsedSeconds=0;runtime=$null;sourceSha256=$null;scriptSha256=$null;helperSha256=$null;javaResult=$null
    process=$null;runtimeProbe=$null;cleanup=$null;failure=$null;syntheticOnly=$true;trainingAuthorized=$false;events=@()}
$report.suite=$Suite
$report.powerShellVersion=$PSVersionTable.PSVersion.ToString()
if($baseline){$report.version='NUMERICAL_PREDICTION_BUNDLE_COLLECTION_V1'}
$docker=$null; $dockerStarted=$false
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('{0}-{1}-{2}.json' -f $prefix,(Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($path.Length+41 -ge 260){throw 'Choose a shorter OutputDirectory so Windows PowerShell can preserve atomic checkpoints.'}
if(Test-Path -LiteralPath $path){throw 'Unique evidence path already exists; refusing to overwrite.'}
function Update-EvaluationProgress([int]$Percent,[string]$Detail){
    Write-Host "[$Percent%] $Detail"
    Write-Progress -Activity 'Numerical evaluation engineering' -Status $Detail -PercentComplete $Percent
    $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;detail=$Detail})
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    Save-NumericalHistoryReport $report $path -Compact
}
try {
    Update-EvaluationProgress 0 'Preparing synthetic-only evidence; no service or model required.'
    $source=(Resolve-Path -LiteralPath $source).Path
    $report.sourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $report.scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    $report.helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1') -Algorithm SHA256).Hash
    $java=Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $javac=Get-Command javac -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($Runtime -eq 'Auto'){$Runtime=if($java -and $javac){'Java'}else{'Docker'}}
    $report.runtime=$Runtime
    if($Runtime -eq 'Java'){
        if(-not $java -or -not $javac){throw 'Local JDK 21+ required; use -Runtime Docker for the cached build image.'}
        $executable=$java.Source
        $arguments=@('-Xmx256m','--source','21',$source,$cliArgument)
    } else {
        $docker=Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $probe=Invoke-EvaluationProcess $docker.Source @('image','inspect',$image,'--format','{{.Id}}') 15
        $report.runtimeProbe=$probe
        if($probe.exitCode -ne 0){throw "Cached JDK image unavailable. No automatic download. Install JDK 21+ or explicitly pull $image then retry."}
        $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=15;detail=('Cached image: '+$probe.stdout.Trim())})
        if($source.Contains(',')){throw 'Docker bind source cannot contain a comma.'}
        $executable=$docker.Source
        $arguments=@('run','--rm','--pull','never','--name',$containerName,'--network','none','--read-only',
            '--cap-drop','ALL','--security-opt','no-new-privileges','--pids-limit','128','--memory','768m','--cpus','1',
            '--tmpfs','/tmp:rw,nosuid,size=128m','--workdir','/tmp','--mount',"type=bind,source=$source,target=/input/NumericalEvaluationEngineering.java,readonly",'--entrypoint','java',
            $image,'-Xmx256m','--source','21','/input/NumericalEvaluationEngineering.java',$cliArgument)
        $dockerStarted=$true
    }
    Update-EvaluationProgress 40 "Running fixed $Suite suite via $Runtime; synthetic data only, no market-data fitting."
    $report.process=Invoke-EvaluationProcess $executable $arguments $TimeoutSeconds
    if($report.process.timedOut){throw 'Synthetic suite timed out; inspect captured evidence.'}
    if($report.process.exitCode -ne 0){throw 'Synthetic Java process failed; inspect embedded stdout/stderr.'}
    Update-EvaluationProgress 85 'Checking complete suite, safety flags and independent metric expectations.'
    $report.javaResult=$report.process.stdout | ConvertFrom-Json
    if($baseline){Assert-NumericalBaselineBundle $report.javaResult}else{Assert-EvaluationSmoke $report.javaResult}
    $report.status='SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED'
    $report.events+=@([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=100;detail='Synthetic checks passed; training remains blocked.'})
} catch {
    $report.status='FAILED';$report.failure=$_.Exception.Message
} finally {
    if($report.status -eq 'RUNNING'){$report.status='INTERRUPTED';$report.failure='Run interrupted before completion.'}
    if($dockerStarted -and $docker){
        # Only the uniquely named container created by this invocation; never the service.
        try{$report.cleanup=Invoke-EvaluationProcess $docker.Source @('rm','--force',$containerName) 15}catch{$report.cleanup=[pscustomobject]@{error=$_.Exception.Message}}
    }
    $timer.Stop();$report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    Save-NumericalHistoryReport $report $path -Compact
    Write-Progress -Activity 'Numerical evaluation engineering' -Completed
    Write-Host ('[100%] {0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds)
    Write-Host "Share this one file: $path"
}
if($report.status -eq 'FAILED'){throw $report.failure}
