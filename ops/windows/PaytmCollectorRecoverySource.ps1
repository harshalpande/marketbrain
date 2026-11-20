function New-CollectorRecoverySource {
 $source=New-DurableCollectorSource 'ab47639ee8d74da69a9466c0f59e601e'
 $call="`$r['collector']=Invoke-DurableCollectorLoop"
 $auth="`$r['applicationBootId']=Test-HealthTokenAuthority `$token"
 if(-not $source.Contains($call) -or -not $source.Contains($auth)){throw 'COLLECTOR_UPGRADE_TEMPLATE_CHANGED'}
 $source=$source.Replace($call,"`$r['collector']=Invoke-CollectorRecoveryLoop")
 $wait="Wait-CollectorApplication {Read-DurableCollectorControl 'C:\ProgramData\MarketBrainPaytmHealth\collector-v1\control.json' 'ab47639ee8d74da69a9466c0f59e601e'}`n  "
 $source=$source.Replace($auth,($wait+$auth))
 return ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmCollectorRecovery.ps1'))+"`n"+$source)
}
