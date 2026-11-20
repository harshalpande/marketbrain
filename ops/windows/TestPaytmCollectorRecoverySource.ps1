$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmHealthScheduledToken.ps1')
. (Join-Path $PSScriptRoot 'PaytmDurableCollectorSetup.ps1')
. (Join-Path $PSScriptRoot 'PaytmCollectorRecoverySource.ps1')
$source=New-CollectorRecoverySource
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'GENERATED_WORKER_PARSE'}
if($source.Contains('$r[''collector'']=Invoke-DurableCollectorLoop') -or -not $source.Contains('$r[''collector'']=Invoke-CollectorRecoveryLoop')){throw 'GENERATED_LOOP_WRONG'}
$wait=$source.IndexOf("Wait-CollectorApplication {Read-DurableCollectorControl")
$auth=$source.IndexOf("`$r['applicationBootId']=Test-HealthTokenAuthority `$token")
if($wait -lt 0 -or $auth -le $wait){throw 'GENERATED_WAIT_ORDER'}
# Replace only the disk reader with a disabled fixture. All worker gate/control code stays real.
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Read-TimeObservationFile'},$true)
if(-not $fn){throw 'DISABLED_GATE_READER_MISSING'}
$source=$source.Remove($fn.Extent.StartOffset,$fn.Extent.EndOffset-$fn.Extent.StartOffset).Insert($fn.Extent.StartOffset,"function Read-TimeObservationFile { @{version=1;installationId='ab47639ee8d74da69a9466c0f59e601e';enabled=`$false} }")
$tmp=Join-Path $env:TEMP ('collector-disabled-'+[guid]::NewGuid().ToString('N')+'.ps1')
try{
 [IO.File]::WriteAllText($tmp,$source,[Text.UTF8Encoding]::new($false))
 $p=[Diagnostics.Process]::new();$p.StartInfo.FileName='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';$p.StartInfo.Arguments='-NoProfile -NonInteractive -File "'+$tmp+'"';$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
 $null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 if(-not $p.WaitForExit(15000)){$p.Kill();throw 'DISABLED_GATE_TIMEOUT'}
 if($p.ExitCode -ne 0 -or $o.Result -or $err.Result){throw 'DISABLED_GATE_EXECUTION'}
}finally{if($p){$p.Dispose()};Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue}
$entry=Join-Path $PSScriptRoot '../automation/CollectorRecoveryUpgrade.Entry.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$t,[ref]$e);if($e.Count){throw 'UPGRADE_ENTRY_PARSE'}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-CollectorUpgradeTaskPreserved'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$before='<Task><Principal>limited</Principal><Settings><Enabled>false</Enabled></Settings><Actions><Exec>old</Exec></Actions></Task>'
Assert-CollectorUpgradeTaskPreserved $before ($before.Replace('old','new'))
foreach($changed in @($before.Replace('limited','admin'),$before.Replace('false','true'))){$failed=$false;try{Assert-CollectorUpgradeTaskPreserved $before $changed}catch{$failed=$true};if(-not $failed){throw 'TASK_DRIFT_ALLOWED'}}
Write-Host 'COLLECTOR_SOURCE_VERIFIED: native PS5 disabled gate, generated wait/loop, action-only XML and two forbidden changes.'
