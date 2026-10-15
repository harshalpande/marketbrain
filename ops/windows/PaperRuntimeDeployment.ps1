# Definitions only. No service access, secret reads or role changes on import.
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
function ConvertTo-PaperRuntimeEnvironment($Entries) {
    $map=@{}
    foreach($entry in $Entries){
        $split=$entry.IndexOf('=');if($split -lt 1){throw 'DEPLOY_ENVIRONMENT_INVALID'}
        $key=$entry.Substring(0,$split);if($map.ContainsKey($key)){throw 'DEPLOY_DUPLICATE_ENVIRONMENT'}
        $map[$key]=$entry.Substring($split+1)
    }
    return $map
}
function ConvertTo-PaperHostMount([string]$Path) {
    $p=$Path.Replace('\','/').TrimEnd('/')
    if($p -match '^/(?:run/desktop/mnt/host|host_mnt)/([a-zA-Z])/(.+)$'){$p=$Matches[1]+':/'+$Matches[2]}
    if($p -notmatch '^[a-zA-Z]:/' -or $p -match '/\.\.?(/|$)'){throw 'DEPLOY_HOST_MOUNT_UNRECOGNIZED'}
    return $p.ToLowerInvariant()
}
function Get-PaperRuntimePolicyEnvironment([string]$Oid) {
    if($Oid -cnotmatch '^[1-9][0-9]{0,9}$'){throw 'DEPLOY_DATABASE_IDENTITY'}
    $p=@{ENABLED='true';ACTIVATION='REVIEW_ONLY';TRANSPORT='PRIVATE_SAME_MACHINE';CREDENTIAL_MODE='PROCESS_MEMORY';HOST='host.docker.internal';PORT='5432';DATABASE='marketbrain';DATABASE_OID=$Oid;POLICY_ID='PAPER_TELEGRAM_TEST_100S_V1';MAX_QUOTE_AGE_MILLIS='15000';MAX_SLIPPAGE_BPS='50';MAX_QUANTITY='1';MAX_ORDER_NOTIONAL_PAISE='500000';MAX_APPROVALS='2';MAX_FILLS='1';MAX_PROPOSAL_LIFETIME_SECONDS='100'}
    $result=@{};foreach($k in $p.Keys){$result['MARKETBRAIN_PAPER_REVIEW_'+$k]=$p[$k]};return $result
}
function Assert-PaperRuntimeContainer($Value,[string]$Repo,[switch]$Memory) {
    if($Value.Id -cnotmatch '^[a-f0-9]{64}$' -or -not $Value.State.Running -or $Value.State.Paused){throw 'DEPLOY_CONTAINER_NOT_RUNNING'}
    $labels=$Value.Config.Labels
    if($labels.'com.docker.compose.service' -cne 'marketbrain-service' -or $labels.'com.docker.compose.project' -cnotmatch '^[a-z0-9][a-z0-9_-]{0,62}$') {throw 'DEPLOY_CONTAINER_IDENTITY'}
    if((ConvertTo-PaperHostMount $labels.'com.docker.compose.project.working_dir') -cne (ConvertTo-PaperHostMount $Repo)){throw 'DEPLOY_WORKSPACE_MISMATCH'}
    $expected=@('compose.yaml','compose.paper-storage.yaml');if($Memory){$expected+='compose.paper-review-memory.yaml'}
    $paths=@($labels.'com.docker.compose.project.config_files' -split ',')
    if($paths.Count -ne $expected.Count){throw 'DEPLOY_COMPOSE_STACK_MISMATCH'}
    for($i=0;$i -lt $paths.Count;$i++){if((ConvertTo-PaperHostMount $paths[$i]) -cne (ConvertTo-PaperHostMount (Join-Path $Repo $expected[$i]))){throw 'DEPLOY_COMPOSE_STACK_MISMATCH'}}
    $ports=@($Value.HostConfig.PortBindings.'8080/tcp')
    if($ports.Count -ne 1 -or $ports[0].HostIp -cne '127.0.0.1' -or $ports[0].HostPort -cne '8080'){throw 'DEPLOY_PORT_BOUNDARY'}
    if(@($Value.HostConfig.PortBindings.PSObject.Properties).Count -ne 1){throw 'DEPLOY_EXTRA_PORT'}
    if($Value.HostConfig.Privileged -or $Value.HostConfig.NetworkMode -cin @('host','none','container')){throw 'DEPLOY_UNSAFE_CONTAINER'}
    $envMap=ConvertTo-PaperRuntimeEnvironment $Value.Config.Env
    if($envMap.MARKETBRAIN_EXECUTION_MODE -cne 'PAPER' -or $envMap.MARKETBRAIN_PAPER_APPROVAL_STORAGE_ENABLED -cne 'true' -or $envMap.MARKETBRAIN_PAPER_APPROVAL_KEY_FILE -cne '/run/secrets/paper-approval.key' -or $envMap.MARKETBRAIN_PAPER_READ_TOKEN -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'DEPLOY_APPLICATION_CONTRACT'}
    if(-not $Memory -and @($envMap.Keys|Where-Object {$_ -clike 'MARKETBRAIN_PAPER_REVIEW_*'}).Count){throw 'DEPLOY_REVIEW_ALREADY_CONFIGURED'}
    if($Memory){
        $policy=Get-PaperRuntimePolicyEnvironment $envMap.MARKETBRAIN_PAPER_REVIEW_DATABASE_OID
        foreach($key in $policy.Keys){if($envMap[$key] -cne $policy[$key]){throw 'DEPLOY_RUNTIME_POLICY_MISMATCH'}}
        if(@($envMap.Keys|Where-Object {$_ -clike 'MARKETBRAIN_PAPER_REVIEW_*'}).Count -ne $policy.Count){throw 'DEPLOY_EXTRA_RUNTIME_SETTING'}
        if($Value.HostConfig.Tmpfs.'/run/marketbrain-writer' -cne 'rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0'){throw 'DEPLOY_CONTROL_MOUNT_MISMATCH'}
    }
    $mounts=@($Value.Mounts|Where-Object {$_.Type -cne 'tmpfs'})
    if($mounts.Count -ne 2){throw 'DEPLOY_EXISTING_MOUNTS_UNEXPECTED'}
    foreach($destination in @('/marketbrain-review','/run/secrets/paper-approval.key')){
        $m=@($mounts|Where-Object Destination -CEQ $destination)
        if($m.Count -ne 1 -or $m[0].Type -cne 'bind' -or $m[0].RW -ne ($destination -ceq '/marketbrain-review')){throw 'DEPLOY_EXISTING_MOUNT_INVALID'}
        [void](ConvertTo-PaperHostMount $m[0].Source)
    }
}
function Assert-PaperRuntimeCompose($Plan,$Before,[string]$Oid,[string]$Image) {
    $service=$Plan.services.'marketbrain-service';$old=ConvertTo-PaperRuntimeEnvironment $Before.Config.Env
    foreach($setting in @('privileged','network_mode','pid','devices','cap_add','entrypoint','command','user')){if($service.PSObject.Properties[$setting]){throw 'DEPLOY_UNREVIEWED_CONTAINER_SETTING'}}
    $desired=@{};foreach($p in $service.environment.PSObject.Properties){$desired[$p.Name]=[string]$p.Value}
    $policy=Get-PaperRuntimePolicyEnvironment $Oid
    foreach($key in $policy.Keys){if($desired[$key] -cne $policy[$key]){throw 'DEPLOY_PLANNED_POLICY_MISMATCH'}}
    $oldKeys=@($old.Keys|Where-Object {$_ -clike 'MARKETBRAIN_*' -and $_ -cnotlike 'MARKETBRAIN_PAPER_REVIEW_*'})
    $newKeys=@($desired.Keys|Where-Object {$_ -cnotlike 'MARKETBRAIN_PAPER_REVIEW_*'})
    if($oldKeys.Count -ne $newKeys.Count -or $desired.Count -ne ($oldKeys.Count+$policy.Count)){throw 'DEPLOY_ENVIRONMENT_DRIFT'}
    foreach($key in $oldKeys){if(-not $desired.ContainsKey($key) -or $desired[$key] -cne $old[$key]){throw 'DEPLOY_ENVIRONMENT_DRIFT'}}
    if($service.image -cne $Image -or $Plan.name -cne $Before.Config.Labels.'com.docker.compose.project'){throw 'DEPLOY_PLANNED_IDENTITY'}
    $ports=@($service.ports);if($ports.Count -ne 1 -or $ports[0].host_ip -cne '127.0.0.1' -or [string]$ports[0].published -cne '8080' -or [string]$ports[0].target -cne '8080' -or $ports[0].protocol -cne 'tcp'){throw 'DEPLOY_PLANNED_PORT'}
    $mounts=@($service.volumes);if($mounts.Count -ne 2){throw 'DEPLOY_PLANNED_MOUNTS'}
    foreach($m in $mounts){
        $oldMount=@($Before.Mounts|Where-Object Destination -CEQ $m.target)
        $readOnly=if($m.PSObject.Properties['read_only']){[bool]$m.read_only}else{$false}
        if($oldMount.Count -ne 1 -or $m.type -cne 'bind' -or (ConvertTo-PaperHostMount $m.source) -cne (ConvertTo-PaperHostMount $oldMount[0].Source) -or $readOnly -eq [bool]$oldMount[0].RW){throw 'DEPLOY_PLANNED_MOUNT_DRIFT'}
    }
    if(@($service.tmpfs).Count -ne 1 -or $service.tmpfs[0] -cne '/run/marketbrain-writer:rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0'){throw 'DEPLOY_PLANNED_CONTROL_MOUNT'}
}
function Assert-PaperRuntimePreserved($Before,$After) {
    $old=ConvertTo-PaperRuntimeEnvironment $Before.Config.Env;$new=ConvertTo-PaperRuntimeEnvironment $After.Config.Env
    foreach($key in @($old.Keys|Where-Object {$_ -clike 'MARKETBRAIN_*'})){if($new[$key] -cne $old[$key]){throw 'DEPLOY_APPLIED_ENVIRONMENT_DRIFT'}}
    if($Before.HostConfig.NetworkMode -cne $After.HostConfig.NetworkMode){throw 'DEPLOY_NETWORK_CHANGED'}
    foreach($m in @($Before.Mounts|Where-Object Type -CEQ 'bind')){
        $n=@($After.Mounts|Where-Object Destination -CEQ $m.Destination)
        if($n.Count -ne 1 -or $n[0].Type -cne 'bind' -or $n[0].RW -ne $m.RW -or (ConvertTo-PaperHostMount $n[0].Source) -cne (ConvertTo-PaperHostMount $m.Source)){throw 'DEPLOY_APPLIED_MOUNT_DRIFT'}
    }
}
