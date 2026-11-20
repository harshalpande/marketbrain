#requires -Version 7.5
param([switch]$Check)
$ErrorActionPreference='Stop'
$base=Join-Path $PSScriptRoot '../windows'
$worker=[IO.File]::ReadAllText((Join-Path $base 'RunPaytmTimeObserver.ps1')).Replace("`r`n","`n")
$header="#requires -Version 7.5`nparam([Parameter(Mandatory)][string]`$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]`$Mode='Observe')`n"
$contract=[IO.File]::ReadAllText((Join-Path $base 'PaytmTimeObservation.ps1'))
$text=$header+'$timeAccountContract = '+"'"+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($contract))+"'`n"+[IO.File]::ReadAllText((Join-Path $base 'PaytmTimeAccountProbe.ps1'))+"`n"+[IO.File]::ReadAllText((Join-Path $base 'PaytmTimeObservation.ps1'))+"`n"+'$timeObserverWorker = '+"'"+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($worker))+"'`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TimeObserver.Entry.ps1'))
$text=$text.Replace("`r`n","`n")
$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if($e.Count -or [Text.Encoding]::UTF8.GetByteCount($text) -gt 65536){throw 'Invalid observer artifact'}
$path=Join-Path $PSScriptRoot 'jobs/PaytmTimeObserver.ps1'
if($Check){if([IO.File]::ReadAllText($path).Replace("`r`n","`n") -cne $text){throw 'Observer artifact out of date'}}else{[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
Write-Host 'TIME_OBSERVER_BUILD_VERIFIED'
