#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmDurableCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmDurableCollectorSetup.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthScheduledToken.ps1')
function Start-Sleep {param($Seconds) if($Seconds -notin @(2,4,8)){throw 'Unbounded delay'};$script:delays+=,$Seconds}
function Invoke-CollectorCycle($Token,$Args,$Boot,[switch]$Revoke){
 if($Revoke){$script:revokes++;return @{revoked=($script:case -ne 'revokeFailure')}}
 $script:cycles++
 if($script:case -eq 'exception'){throw 'fixture secret exception'}
 $ok=($script:case -ne 'rejected' -and -not ($script:case -eq 'recovery' -and $script:cycles -eq 1))
 @{accepted=$ok;healthySubmitted=$ok}
}
foreach($script:case in @('healthy','recovery','rejected','exception','revokeFailure','controlFailure','saveFailure')){
 $script:cycles=0;$script:reads=0;$script:revokes=0;$script:delays=@();$script:saved=@()
 $enabled={ $script:reads++;if($script:case -eq 'controlFailure'){throw 'bad control'};return ($script:reads -le 3)}
 $save={param($v) if($script:case -eq 'saveFailure' -and $v.phase -ne 'FAILED'){throw 'disk failure'};$script:saved+=,$v.Clone()}
 $r=Invoke-DurableCollectorLoop 'DO_NOT_EXPORT' @() 'boot' $enabled $save
 if(($r.phase -eq 'STOPPED') -ne ($case -in @('healthy','recovery')) -or ($r|ConvertTo-Json) -match 'DO_NOT_EXPORT|fixture secret'){throw "Runtime case failed: $case"}
 if($case -in @('rejected','exception') -and ($script:cycles -ne 3 -or $r.failure -ne 'COLLECTOR_FAILURE_LIMIT')){throw 'Failure retry limit missing'}
 if($case -eq 'recovery' -and ($r.acceptedCount -ne 2 -or $r.consecutiveFailures -ne 0)){throw 'Recovery failed'}
 if($script:revokes -lt 1){throw 'Final revocation omitted'}
}
function Resolve-TimeAccountTaskSid($Identity){return $Identity}
$d=Get-DurableCollectorDefinition ('A'*64)
foreach($case in @('valid','enabled','admin','trigger','arguments','restart','timeout')){
 $t=@{TaskName=$d.name;TaskPath='\';State='Disabled';Principal=@{UserId='S-1-5-21-3041730714-102984520-3202743044-1011';LogonType='Password';RunLevel='Limited'};Actions=@(@{Execute=$d.exe;Arguments=$d.arguments;WorkingDirectory=$d.root});Triggers=@(@{Enabled=$true;CimClass=@{CimClassName='MSFT_TaskBootTrigger'}});Settings=@{Enabled=$false;MultipleInstances='IgnoreNew';RestartCount=0;ExecutionTimeLimit='PT0S';DisallowStartIfOnBatteries=$false;StopIfGoingOnBatteries=$false;StartWhenAvailable=$true}}
 switch($case){enabled{$t.Settings.Enabled=$true} admin{$t.Principal.RunLevel='Highest'} trigger{$t.Triggers=@()} arguments{$t.Actions[0].Arguments='changed'} restart{$t.Settings.RestartCount=99} timeout{$t.Settings.ExecutionTimeLimit='PT1M'}}
 $failed=$false;try{Assert-DurableCollectorTask $t $d}catch{$failed=$true}
 if($failed -ne ($case -ne 'valid')){throw "Task validation failed: $case"}
}
$source=New-DurableCollectorSource ('a'*32)
$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count -or $source -match '__RUN__|__WORK__|__ROOT__|__KNOWN__|__RESULT__|__TOKEN_CHECK__'){throw 'Generated persistent worker invalid'}
# Exercise actual generated worker startup gate in a child PS5: no custody/network calls while disabled.
$dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-durable-fixture-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
$source=$source.Replace("if(-not (Read-DurableCollectorControl", "function Read-DurableCollectorControl {return `$false}`nif(-not (Read-DurableCollectorControl")
$path=Join-Path $dir 'worker.ps1';[IO.File]::WriteAllText($path,$source)
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $path
if($LASTEXITCODE -ne 0){throw 'Disabled worker did not exit before custody/network access'}
Write-Host 'DURABLE_COLLECTOR_FIXTURES_PASSED: 7 runtime paths, 7 task definitions, generated PS5 parsing and actual disabled-worker exit.'
