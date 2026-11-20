# Read-only verification of the accepted spare-machine installation.
function Assert-DurableCollectorReceipt($Receipt) {
 if($Receipt.version -ne 1 -or $Receipt.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $Receipt.status -cne 'DURABLE_COLLECTOR_STAGED_DISABLED_ACTIVATION_PENDING' -or $Receipt.failure -or $Receipt.taskRegistered -ne $true -or $Receipt.disabledVerified -ne $true -or $Receipt.workerStarted -ne $false -or $Receipt.ordersEnabled -ne $false){throw 'COLLECTOR_RECEIPT_STATE'}
 if($Receipt.workerSha256 -cne '25CFF7A9A54184DC0B5F43A094B331B14C4D288448C8BA8A01975A9F29053B99' -or $Receipt.knownHostsSha256 -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D' -or $Receipt.taskXmlSha256 -cne '4D5EFBB0271BF6EB937050E89B5118CBDCE89FF9AC30AF1FD7F8C10EC8E6B730'){throw 'COLLECTOR_RECEIPT_PINS'}
 if($Receipt.credentialCheck.accepted -ne $true -or $Receipt.credentialCheck.win32Code -ne 0 -or $Receipt.credentialCheck.logonType -cne 'BATCH' -or $Receipt.credentialCheck.resolvedSid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011'){throw 'COLLECTOR_RECEIPT_IDENTITY'}
}
function Get-DurableCollectorStagingPreflight($Receipt) {
 Assert-DurableCollectorReceipt $Receipt
 $d=Get-DurableCollectorDefinition $Receipt.workerSha256
 foreach($path in @('C:\ProgramData\MarketBrainPaytmHealth',$d.root,(Join-Path $d.root 'worker.ps1'),(Join-Path $d.root 'known_hosts'),(Join-Path $d.root 'control.json'))){Assert-TimeObservationAcl $path}
 if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $Receipt.workerSha256 -or (Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash -cne $Receipt.knownHostsSha256){throw 'COLLECTOR_INSTALLED_FILE_DRIFT'}
 $control=Read-TimeObservationFile (Join-Path $d.root 'control.json')
 if($control.version -ne 1 -or $control.installationId -cne $Receipt.runId -or $control.enabled -isnot [bool] -or $control.enabled){throw 'COLLECTOR_CONTROL_DRIFT'}
 $task=Get-ScheduledTask -TaskName $d.name -TaskPath '\' -ErrorAction Stop
 Assert-DurableCollectorTask $task $d
 if($task.Description -cne ('MarketBrain diagnostic collector '+$Receipt.runId)){throw 'COLLECTOR_TASK_OWNERSHIP'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$xmlHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $d.name -TaskPath '\'))))).Replace('-','')}finally{$sha.Dispose()}
 if($xmlHash -cne $Receipt.taskXmlSha256){throw 'COLLECTOR_TASK_XML_DRIFT'}
 $snapshot=Read-TimeObservation
 return @{status='DURABLE_COLLECTOR_STAGING_VERIFIED_ACTIVATION_PENDING';installationId=$Receipt.runId;taskDisabled=$true;controlDisabled=$true;workerHashVerified=$true;hostHashVerified=$true;taskXmlVerified=$true;timeSnapshotAgeSeconds=$snapshot.ageSeconds;observedUtc=[DateTime]::UtcNow.ToString('o');ordersEnabled=$false;runtimeStarted=$false}
}
