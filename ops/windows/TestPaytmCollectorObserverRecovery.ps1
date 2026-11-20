$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmCollectorObserverRecovery.ps1')
function New-ObserverFixture {
 @{TaskName='MarketBrain-Time-Observer-v1';TaskPath='\';Description='MarketBrain fixed read-only Windows time observer v1';Principal=@{UserId='SYSTEM';LogonType='ServiceAccount';RunLevel='Highest'};Actions=@(@{Execute='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';Arguments='pinned';WorkingDirectory=''});Settings=@{Enabled=$true;MultipleInstances='IgnoreNew';ExecutionTimeLimit='PT0S'};State='Ready';Triggers=@(@{Enabled=$true;CimClass=@{CimClassName='MSFT_TaskBootTrigger'}})}
}
Assert-CollectorObserverTask (New-ObserverFixture) 'pinned'
foreach($case in @('owner','principal','action','directory','disabled','state','trigger','parallel','duration')){
 $t=New-ObserverFixture
 switch($case){owner{$t.Description='other'} principal{$t.Principal.UserId='other'} action{$t.Actions[0].Arguments='other'} directory{$t.Actions[0].WorkingDirectory='other'} disabled{$t.Settings.Enabled=$false} state{$t.State='Disabled'} trigger{$t.Triggers[0].Enabled=$false} parallel{$t.Settings.MultipleInstances='Parallel'} duration{$t.Settings.ExecutionTimeLimit='PT1H'}}
 $failed=$false;try{Assert-CollectorObserverTask $t 'pinned'}catch{$failed=$true};if(-not $failed){throw ('OBSERVER_GUARD_'+$case)}
}
Write-Host 'COLLECTOR_OBSERVER_GUARDS_PASSED: valid identity and nine forbidden changes.'
