#Requires -Version 7.2
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $root
$docker=(Get-Command docker.exe -CommandType Application|Select-Object -First 1).Source
if(-not $docker){throw 'Docker executable not found.'}
Write-Host '[10%] Resolving the existing MarketBrain Compose deployment.'
$ids=@(& $docker ps -aq --filter 'label=com.docker.compose.service=marketbrain-service')
if($LASTEXITCODE -ne 0 -or $ids.Count -ne 1){throw 'Expected exactly one existing MarketBrain Compose service.'}
$inspect=(& $docker inspect $ids[0]|ConvertFrom-Json)[0]
if($LASTEXITCODE -ne 0){throw 'Container inspection failed.'}
$labels=$inspect.Config.Labels
if([IO.Path]::GetFullPath($labels.'com.docker.compose.project.working_dir').TrimEnd('\') -ine $root.TrimEnd('\')){throw 'Existing deployment belongs to a different working directory.'}
$files=@($labels.'com.docker.compose.project.config_files' -split ',')
$override=Join-Path $root 'compose.paytm-supervised.yaml'
if($files -notcontains $override){$files+=$override}
$args=@('compose','--project-name',[string]$labels.'com.docker.compose.project')
foreach($file in $files){
 $full=[IO.Path]::GetFullPath($file)
 if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Compose file is outside the repository or missing.'}
 $args+=@('-f',$full)
}
Write-Host '[30%] Building supervised login into the application. Existing Compose overrides retained.'
& $docker @args build marketbrain-service
if($LASTEXITCODE -ne 0){throw 'Build failed; existing service was not replaced.'}
Write-Host '[75%] Recreating only the application service.'
& $docker @args up -d --no-deps marketbrain-service
if($LASTEXITCODE -ne 0){throw 'Application deployment failed.'}
$watch=[Diagnostics.Stopwatch]::StartNew();$ready=$false
do{
 try{$r=Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -NoProxy -TimeoutSec 5;if($r.status -eq 'UP'){$ready=$true;break}}catch{}
 Write-Progress -Activity 'Application startup' -PercentComplete 90 -Status "$([int]$watch.Elapsed.TotalSeconds)/180 seconds"
 Start-Sleep -Seconds 3
}while($watch.Elapsed.TotalSeconds -lt 180)
Write-Progress -Activity 'Application startup' -Completed
if(-not $ready){throw 'Application health not UP. Inspect application logs before login.'}
Write-Host '[100%] Application UP. Run StartPaytmSupervisedLogin.ps1 in elevated PowerShell 7 on this laptop.'
