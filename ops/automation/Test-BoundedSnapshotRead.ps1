#requires -Version 7.5
$ErrorActionPreference='Stop'
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1'),[ref]$t,[ref]$e)
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BoundedJson'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-snapshot-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $dir
$path=Join-Path $dir 'status.json';[IO.File]::WriteAllText($path,'{"sequence":0}')
$writer=[PowerShell]::Create()
$null=$writer.AddScript({param($p)
    foreach($i in 1..250){$tmp=$p+'.new';[IO.File]::WriteAllText($tmp,('{"sequence":'+$i+'}'));[IO.File]::Replace($tmp,$p,[Management.Automation.Language.NullString]::Value);Start-Sleep -Milliseconds 2}
}).AddArgument($path)
$pending=$writer.BeginInvoke()
try{foreach($i in 1..300){$v=Read-BoundedJson $path;if($v.sequence -lt 0 -or $v.sequence -gt 250){throw 'Torn snapshot'}};$null=$writer.EndInvoke($pending);if($writer.HadErrors){throw ($writer.Streams.Error|Out-String)}}finally{$writer.Dispose()}
[IO.File]::WriteAllText($path,('x'*65537));$large=$false;try{$null=Read-BoundedJson $path}catch{$large=$_.Exception.Message -eq 'STATE_TOO_LARGE'};if(-not $large){throw 'Size bound lost'}
[IO.File]::WriteAllText($path,'{"sequence":1}')
$held=[IO.File]::Open($path,'Open','ReadWrite','None');$failed=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
try{try{$null=Read-BoundedJson $path}catch{$failed=$_.Exception.GetBaseException() -is [IO.IOException]}}finally{$held.Dispose()}
if(-not $failed -or $watch.Elapsed.TotalSeconds -gt 3){throw 'Persistent lock not bounded'}
Write-Host 'BOUNDED_SNAPSHOT_PASSED: 300 reads with 250 atomic replacements, size bound, persistent-lock limit.'
