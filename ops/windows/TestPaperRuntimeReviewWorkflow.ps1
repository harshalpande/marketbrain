#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
$count=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Assertion failed: $Name"};$script:count++}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action}catch{$caught=$true};Check $caught $Name}
$id='1'*32
$names=@('spring_memory_mode_starts_locked_without_database','approved_100_second_policy_registered','no_publisher_or_execution_bean','locked_callback_never_dials','unix_socket_has_private_permissions','status_starts_locked','stdin_frame_unlocks_process_secret','identical_unlock_replay_is_safe','different_secret_cannot_overwrite','malformed_secret_refused','only_socket_metadata_on_filesystem','explicit_lock_removes_ready_secret','unlock_after_lock_allowed','shutdown_removes_owned_socket','fresh_spring_context_requires_new_unlock','stale_socket_path_never_overwritten','broad_directory_permissions_refused','no_database_attempts_across_suite')
function New-OfflineRuntimeFixture {
    return [pscustomobject]@{version='PAPER_RUNTIME_FIXTURE_V1';runId=$id;bootId='11111111-1111-1111-1111-111111111111';status='RUNTIME_FIXTURE_READY_LOCKED';applicationDatabaseAccessed=$false;realCredentialUsed=$false;realTelegramVerified=$false;actionExecutionEnabled=$false;checkCount=18;failedCount=0;checks=@($names|ForEach-Object{[pscustomobject]@{name=$_;passed=$true;elapsedMillis=1}})}
}
$value=New-OfflineRuntimeFixture;Assert-PaperRuntimeFixture $value $id;Check $true 'complete receipt'
Assert-PaperRuntimeFixture ($value|ConvertTo-Json -Depth 8|ConvertFrom-Json) $id;Check $true 'JSON integer roundtrip'
foreach($field in @('applicationDatabaseAccessed','realCredentialUsed','realTelegramVerified','actionExecutionEnabled')){
    foreach($bad in @($true,'false',$null)){$v=New-OfflineRuntimeFixture;$v.$field=$bad;Reject {Assert-PaperRuntimeFixture $v $id} ('unsafe '+$field)}
}
foreach($field in @('version','status','bootId','runId')){$v=New-OfflineRuntimeFixture;$v.$field='bad';Reject {Assert-PaperRuntimeFixture $v $id} ('identity '+$field)}
foreach($bad in @('18',17,19,$null)){$v=New-OfflineRuntimeFixture;$v.checkCount=$bad;Reject {Assert-PaperRuntimeFixture $v $id} 'count type/quantity'}
foreach($index in 0..17){$v=New-OfflineRuntimeFixture;$v.checks[$index].passed=$false;Reject {Assert-PaperRuntimeFixture $v $id} ('failed scenario '+$index)}
$v=New-OfflineRuntimeFixture;$v.checks[1].name=$v.checks[0].name;Reject {Assert-PaperRuntimeFixture $v $id} 'duplicate scenario'
foreach($state in @('LOCKED','UNLOCKED','REFUSED')){
    $v=[pscustomobject]@{version='PAPER_RUNTIME_CONTROL_V1';state=$state;databaseAuthenticationVerified=$false;actionExecutionEnabled=$false}
    Assert-PaperRuntimeControl $v $state;Check $true ('control '+$state)
    $v.databaseAuthenticationVerified=$true;Reject {Assert-PaperRuntimeControl $v $state} 'unlock is not authentication'
}
$bytes=[Text.Encoding]::ASCII.GetBytes(('ab'*32))
try {
    $script:calls=[Collections.Generic.List[string]]::new()
    Invoke-PaperRuntimeHandoffSequence {param($command,$input,$expected) $script:calls.Add($command+':'+$expected)} {$script:calls.Add('RESTART')} $bytes
    Check (($script:calls -join ',') -ceq 'STATUS:LOCKED,UNLOCK:UNLOCKED,UNLOCK:UNLOCKED,STATUS:UNLOCKED,RESTART,STATUS:LOCKED,UNLOCK:UNLOCKED,LOCK:LOCKED,STATUS:LOCKED') 'bounded sequence and restart'
    foreach($failure in @('UNLOCK','RESTART','LOCK')){
        $script:calls=[Collections.Generic.List[string]]::new()
        Reject {Invoke-PaperRuntimeHandoffSequence {param($c,$b,$e) $script:calls.Add($c);if($c -ceq $failure){throw 'synthetic lost acknowledgement'}} {if($failure -ceq 'RESTART'){throw 'synthetic restart failure'}} $bytes} ('propagate '+$failure)
        Check ($script:calls.Contains('LOCK')) ('attempt lock after '+$failure)
    }
    Reject {Invoke-PaperRuntimeHandoffSequence {} {} (New-Object byte[] 63)} 'bad input fails before handoff'
    # Real harmless subprocess only; no Docker, database, model or provider activity.
    $exe=Join-Path $PSHOME 'pwsh.exe';$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $v=Invoke-PaperRuntimeProcess $exe @('-NoProfile','-NonInteractive','-Command','$b=[Console]::OpenStandardInput().ReadBytes(64)') $repo 10
    # The invalid child method must be a reported exit, never silently accepted by the bundle.
    Check ($v.exitCode -ne 0) 'native failure exit retained'
    $v=Invoke-PaperRuntimeProcess $exe @('-NoProfile','-NonInteractive','-Command','$stream=[Console]::OpenStandardInput();$buffer=New-Object byte[] 65;$total=0;while(($n=$stream.Read($buffer,$total,65-$total)) -gt 0){$total+=$n};[Console]::Write($total)') $repo 10 $bytes
    Check ($v.exitCode -eq 0 -and $v.stdout -ceq '64') 'stdin payload delivered without arguments'
    Reject {Invoke-PaperRuntimeProcess $exe @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 8') $repo 1} 'child deadline enforced'
}finally{[Array]::Clear($bytes,0,$bytes.Length)}
function Test-Runner([string]$Scenario) {
    # Execute the real runner body with Docker/git boundaries replaced, not a separate reimplementation.
    $runner=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TestPaperRuntimeReviewBundle.ps1') -Raw
    $runner=$runner.Replace(". (Join-Path `$PSScriptRoot 'PaperRuntimeReview.ps1')",'')
    $runner=$runner.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
    $script:mock=[ordered]@{scenario=$Scenario;id=$null;ready=$false;boot=1;removed=$false;stopped=$false;calls=@()}
    function git { $global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40} }
    function Get-Command {param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source='synthetic-docker.exe'} }
    function Start-Sleep {param($Seconds,$Milliseconds)}
    function Invoke-PaperRuntimeProcess($Executable,$Arguments,$Directory,$LimitSeconds,$InputBytes) {
        $script:mock.calls+=($Arguments -join ' ');$output='';$exit=0
        switch($Arguments[0]) {
            'version' {$output='linux'}
            'build' {if($Scenario -ceq 'build-failure'){$exit=1}}
            'image' {$output='sha256:'+('a'*64)}
            'run' {$script:mock.id=$Arguments[-1];$output='b'*64;if($Scenario -ceq 'unknown-create'){$exit=1}}
            'inspect' {
                switch -Wildcard ($Arguments[2]) {
                    '*NetworkMode*' {$output=if($Scenario -ceq 'unsafe-network'){'bridge'}else{'none'}}
                    '*ReadonlyRootfs*' {$output='true'}
                    '*marketbrain.paper.runtime*' {$output=if($Scenario -ceq 'wrong-owner'){'wrong-owner'}else{$script:mock.id}}
                    default {throw 'Unexpected mock inspect'}
                }
            }
            'logs' {
                $fixture=New-OfflineRuntimeFixture;$fixture.runId=$script:mock.id
                $fixture.bootId=if($script:mock.boot -eq 1 -or $Scenario -ceq 'stale-restart'){'11111111-1111-1111-1111-111111111111'}else{'22222222-2222-2222-2222-222222222222'}
                if($Scenario -ceq 'failed-fixture'){$fixture.checks[0].passed=$false;$fixture.failedCount=1}
                $output='PAPER_RUNTIME_REPORT='+($fixture|ConvertTo-Json -Depth 6 -Compress)
            }
            'exec' {
                $command=$Arguments[-1]
                if($command -ceq 'UNLOCK'){
                    Check ($InputBytes.Length -eq 64) 'runner passes secret on stdin'
                    Check (-not (($Arguments -join ' ').Contains([Text.Encoding]::ASCII.GetString($InputBytes)))) 'runner omits secret from arguments'
                    $script:mock.ready=$true;if($Scenario -ceq 'lost-unlock'){$exit=1}
                }
                if($command -ceq 'LOCK'){$script:mock.ready=$false}
                $output=@{version='PAPER_RUNTIME_CONTROL_V1';state=$(if($script:mock.ready){'UNLOCKED'}else{'LOCKED'});databaseAuthenticationVerified=$false;actionExecutionEnabled=$false}|ConvertTo-Json -Compress
            }
            'restart' {$script:mock.boot++;$script:mock.ready=$false}
            'stop' {$script:mock.stopped=$true}
            'rm' {$script:mock.removed=$true}
            default {throw 'Unexpected mock command'}
        }
        return @{exitCode=$exit;stdout=$output;stderr='';elapsedSeconds=0.001}
    }
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-runtime-offline-'+[guid]::NewGuid().ToString('N'))
    $failed=$false
    try{& ([scriptblock]::Create($runner)) -OutputDirectory $dir}catch{$failed=$true}
    $reports=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($reports.Count -eq 1) ('one evidence file '+$Scenario)
    $r=Get-Content -LiteralPath $reports[0].FullName -Raw|ConvertFrom-Json
    if($Scenario -ceq 'success'){
        Check (-not $failed -and $r.status -ceq 'ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING') 'real runner success'
        Check ($r.dpapiRoundTripVerified -and $r.handoffSequencePassed -and $r.cleanupComplete -and $r.finalState -ceq 'LOCKED') 'all success gates'
        Check ($r.fixture.bootId -cne $r.postRestartFixture.bootId) 'fresh boot receipt required'
        Check ($script:mock.stopped -and $script:mock.removed) 'successful fixture cleanup'
    }else{
        Check ($failed -and $r.status -ceq 'FAILED') ('failure propagated '+$Scenario)
        Check (-not $script:mock.removed) ('failed fixture retained '+$Scenario)
        if($Scenario -ceq 'wrong-owner'){Check (-not $script:mock.stopped) 'unknown owner never stopped'}
        if($Scenario -ceq 'lost-unlock'){Check (-not $script:mock.ready) 'lost unlock acknowledgement locks fixture'}
    }
    Check (-not $r.realCredentialUsed -and -not $r.realTelegramVerified -and -not $r.applicationDatabaseAccessed -and -not $r.applicationWriterActivated -and -not $r.actionExecutionEnabled) 'scope flags'
}
foreach($case in @('success','build-failure','unknown-create','unsafe-network','failed-fixture','lost-unlock','stale-restart','wrong-owner')){Test-Runner $case}
Write-Host "PASS: $count offline assertions including eight mocked runner scenarios. No Docker, database, real credentials or Telegram calls."
