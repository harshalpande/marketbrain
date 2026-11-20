# Fixed acceptance of the installed recovery worker; historical v1 receipts remain unchanged.
function Get-RecoveryCollectorReceipt {
 $v=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\collector-v1\recovery-upgrade.json'
 if($v.runId -cne '444dcaf7d25241c5a6e391d243f7eebe' -or $v.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $v.status -cne 'COLLECTOR_RECOVERY_UPGRADED_DISABLED_RUNTIME_PENDING' -or $v.passed -ne $true -or $v.failure -or $v.ordersEnabled -ne $false -or $v.workerStarted -ne $false){throw 'RECOVERY_INSTALL_RECEIPT'}
 if($v.workerSha256 -cne 'F4C496DBBBB1CF55A1A3FA8E2BAD29AE832166E97A5A633F10A3C2C313CCFF4B' -or $v.taskXmlSha256 -cne '968E8E23E13263CC89A026084E0534A9692DB31FD0D60091870C817824674F11'){throw 'RECOVERY_INSTALL_PINS'}
 # Activation expects runId to identify the installation, not the upgrade attempt.
 @{runId=$v.installationId;workerSha256=$v.workerSha256;taskXmlSha256=$v.taskXmlSha256}
}
function Get-RecoveryCollectorPreflight($Receipt){
 $accepted=Get-RecoveryCollectorReceipt
 if($Receipt.runId -cne $accepted.runId -or $Receipt.workerSha256 -cne $accepted.workerSha256){throw 'RECOVERY_RECEIPT_CHANGED'}
 $d=Get-DurableCollectorDefinition $accepted.workerSha256
 foreach($name in @('worker.ps1','known_hosts','control.json')){Assert-TimeObservationAcl (Join-Path $d.root $name)}
 if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $accepted.workerSha256 -or (Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D'){throw 'RECOVERY_FILES_CHANGED'}
 Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
 $xml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($xml)))
 if($hash -cne $accepted.taskXmlSha256){throw 'RECOVERY_TASK_XML_CHANGED'}
 if(Read-DurableCollectorControl (Join-Path $d.root 'control.json') $accepted.runId){throw 'RECOVERY_CONTROL_ENABLED'}
 $time=Read-TimeObservation
 @{passed=$true;workerHashVerified=$true;taskXmlVerified=$true;disabledVerified=$true;timeSnapshotAgeSeconds=$time.ageSeconds;ordersEnabled=$false}
}
function Assert-RecoveryPriorReports($Status,$Final){
 if($Final.runId -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'RECOVERY_PRIOR_INSTALLATION'}
 foreach($v in @($Status,$Final.collector)){
  if($v.version -ne 1 -or $v.instanceId -cne '9e0e85a010c2457887faa0fe8efdb6a1' -or $v.processId -ne 4400 -or $v.phase -cne 'FAILED' -or $v.failure -cne 'COLLECTOR_REVOCATION_UNCONFIRMED' -or $v.acceptedCount -ne 13 -or $v.sequence -ne 18 -or $v.ordersEnabled -ne $false){throw 'RECOVERY_PRIOR_REPORT_CHANGED'}
 }
}
function Preserve-RecoveryPriorReports($Definition){
 if(Test-Path -LiteralPath (Join-Path $Definition.root 'recovery-activation-attempt.json')){throw 'RECOVERY_ATTEMPT_ALREADY_EXISTS'}
 $checkpoint=Read-TimeObservationFile (Join-Path $Definition.root 'signout-checkpoint.json')
 if($checkpoint.runId -cne '73fc2f10891346768bdc0f88e978da75' -or $checkpoint.phase -cne 'REVIEW_REQUIRED'){throw 'RECOVERY_CHECKPOINT_CHANGED'}
 $s=Read-BoundedJson (Join-Path $Definition.work 'status.json');$f=Read-BoundedJson (Join-Path $Definition.work 'final.json');Assert-RecoveryPriorReports $s $f
 $archive=Join-Path $Definition.root 'prior-signout-9e0e85a010c2457887faa0fe8efdb6a1'
 if(Test-Path -LiteralPath $archive){throw 'RECOVERY_ARCHIVE_EXISTS'}
 $null=New-Item -ItemType Directory -Path $archive;Assert-TimeObservationAcl $archive
 foreach($name in @('status.json','final.json')){
  $path=Join-Path $Definition.work $name
  if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_PRIOR_REPARSE'}
  $hash=(Get-FileHash -LiteralPath $path).Hash;$target=Join-Path $archive $name
  Copy-Item -LiteralPath $path -Destination $target -ErrorAction Stop
  if((Get-FileHash -LiteralPath $target).Hash -cne $hash){throw 'RECOVERY_ARCHIVE_HASH'}
 }
 foreach($name in @('status.json','final.json')){
  $path=Join-Path $Definition.work $name
  if((Get-FileHash -LiteralPath $path).Hash -cne (Get-FileHash -LiteralPath (Join-Path $archive $name)).Hash){throw 'RECOVERY_PRIOR_RACE'}
  Remove-Item -LiteralPath $path -ErrorAction Stop
 }
}
function ConvertTo-RecoveryActivationSource([string]$Source){
 $pairs=@{
  "`$receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'"=' $receipt=Get-RecoveryCollectorReceipt';
  'Get-DurableCollectorStagingPreflight $receipt'='Get-RecoveryCollectorPreflight $receipt';
  ' Preserve-CollectorRejectedAttempt $d'=' Preserve-RecoveryPriorReports $d';
  "`$claim=Join-Path `$d.root 'activation-attempt.json'"="`$claim=Join-Path `$d.root 'recovery-activation-attempt.json'";
  '$Value.version -ne 1'='$Value.version -ne 2';
  'DURABLE_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'='RECOVERY_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'
 }
 foreach($old in $pairs.Keys){if(-not $Source.Contains($old)){throw 'RECOVERY_ACTIVATION_TEMPLATE_DRIFT'};$Source=$Source.Replace($old,$pairs[$old])}
 return $Source
}
