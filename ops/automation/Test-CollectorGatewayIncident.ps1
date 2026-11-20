$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CollectorGatewayIncident.ps1')
foreach($case in @('valid','instance','failure','sequence','phase','orders','stage')){
 $s=@{instanceId='c592dec90f904b9da35d7f9dbf1b4226';failure='TRANSPORT_CONFIG_UNAVAILABLE';installationId='ea8b91471cf048aa97a0f6b939b355c7';phase='BLOCKED';sequence=157;processId=8420;ordersEnabled=$false;brokerReady=$false}
 $b=@{instanceId=$s.instanceId;failure=$s.failure};$f=@{instanceId=$s.instanceId;failure=$s.failure;stage='OBSERVATION_LOOP'}
 switch($case){instance{$b.instanceId='other'} failure{$s.failure='KEY_DENIED'} sequence{$s.sequence=158} phase{$s.phase='TRANSPORT_READY'} orders{$s.ordersEnabled=$true} stage{$f.stage='IDENTITY'}}
 $failed=$false;try{Assert-CollectorGatewayIncident $s $b $f}catch{$failed=$true};if($failed -ne ($case -ne 'valid')){throw ('INCIDENT_CASE_'+$case)}
}
foreach($case in @('valid','guard','race')){
 $root=Join-Path $env:TEMP ('mb-incident-'+[guid]::NewGuid().ToString('N'));$archive=Join-Path $root 'archive';$null=New-Item -ItemType Directory -Path $archive
 $before=@{reviewedIncident=$true;incidentHashes=@{}}
 foreach($name in @('status.json','blocked.json','startup-failure.json')){$p=Join-Path $root $name;[IO.File]::WriteAllText($p,'{}');$before.incidentHashes[$name]=(Get-FileHash -LiteralPath $p).Hash}
 $ctx=@{work=$root;archive=$archive;guardXmlHash=$(if($case -ne 'guard'){'pinned'}else{$null})}
 if($case -eq 'race'){[IO.File]::WriteAllText((Join-Path $root 'blocked.json'),'{"changed":true}')}
 $failed=$false;try{Preserve-CollectorGatewayIncident $ctx $before}catch{$failed=$true}
 if($failed -ne ($case -ne 'valid')){throw 'INCIDENT_ARCHIVE_CASE'}
 if(-not (Test-Path -LiteralPath (Join-Path $root 'status.json'))){throw 'STATUS_REMOVED'}
 foreach($name in @('blocked.json','startup-failure.json')){if((Test-Path -LiteralPath (Join-Path $root $name)) -ne $failed){throw 'MARKER_PRESERVATION'}}
}
Write-Host 'GATEWAY_INCIDENT_TESTS_PASSED: seven identity cases, guarded archival and two rejection paths.'
