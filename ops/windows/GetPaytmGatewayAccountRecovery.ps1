#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review',[switch]$LibraryOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')

function ConvertTo-PaytmRecoveryManifest($Saved) {
    $c=Get-PaytmAccountContract
    if($null -eq $Saved -or $Saved -is [array] -or $Saved.version -ne 1 -or
        $Saved.name -cne $c.name -or $Saved.root -cne $c.root -or
        $Saved.sid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or
        $Saved.runId -cnotmatch '^[a-f0-9]{32}$' -or
        $Saved.containsPrivateKey -isnot [bool] -or $Saved.containsPrivateKey -ne $false -or
        (($Saved.previousAgentStatus -cne 'Stopped' -or $Saved.previousAgentStartType -cne 'Disabled') -and
         ($Saved.previousAgentStatus -cne 'Running' -or $Saved.previousAgentStartType -cne 'Automatic'))){
        throw 'RECOVERY_MANIFEST_CONTRACT_INVALID'
    }
    # Allowlist only; never emit arbitrary manifest properties/content.
    [pscustomobject]@{version=1;sid=[string]$Saved.sid;runId=[string]$Saved.runId;
        previousAgentStatus=[string]$Saved.previousAgentStatus;previousAgentStartType=[string]$Saved.previousAgentStartType;containsPrivateKey=$false}
}
function Read-PaytmRecoveryManifest([string]$Path) {
    $null=Assert-PaytmAccountPath $Path
    $stream=[IO.File]::Open($Path,'Open','Read','Read')
    try{
        if($stream.Length -gt 8192){throw 'RECOVERY_MANIFEST_SIZE'}
        $reader=[IO.StreamReader]::new($stream)
        try{
            $buffer=[char[]]::new(8193);$count=$reader.ReadBlock($buffer,0,$buffer.Length)
            if($count -gt 8192){throw 'RECOVERY_MANIFEST_SIZE'}
            $json=[string]::new($buffer,0,$count)
            if(-not $json.TrimStart().StartsWith('{')){throw 'RECOVERY_MANIFEST_JSON'}
            ConvertTo-PaytmRecoveryManifest ($json|ConvertFrom-Json -ErrorAction Stop)
        }finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Get-PaytmRecoveryPath([string]$Path,[bool]$Directory) {
    $null=Assert-PaytmAccountPath $Path
    try{$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop}
    catch [Management.Automation.ItemNotFoundException]{return [pscustomobject]@{exists=$false}}
    if($item.PSIsContainer -ne $Directory){throw 'RECOVERY_PATH_TYPE_UNEXPECTED'}
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|ForEach-Object {
        [pscustomobject]@{sid=$_.IdentityReference.Value;rights=[string]$_.FileSystemRights;type=[string]$_.AccessControlType;inherited=$_.IsInherited;inheritance=[string]$_.InheritanceFlags;propagation=[string]$_.PropagationFlags}
    })
    $result=[ordered]@{exists=$true;ownerSid=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value;protected=$acl.AreAccessRulesProtected;rules=$rules}
    if($Directory){
        # Metadata only, non-recursive and capped. Never read key/profile/work files.
        $children=@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop|Select-Object -First 101)
        $result.immediateEntriesObserved=$children.Count;$result.entryCountCapped=($children.Count -eq 101)
        $result.reparseEntriesObserved=@($children|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count
        $result.unexpectedEntriesObserved=@($children|Where-Object {$_.Name -cnotin @('work','installation.json')}).Count
    }
    [pscustomobject]$result
}
function Get-PaytmRecoveryRelation($Account,$Manifest) {
    if($null -eq $Manifest){return 'MANIFEST_UNAVAILABLE_REVIEW_REQUIRED'}
    if($null -eq $Account){return 'ACCOUNT_ABSENT_MANIFEST_REMAINS'}
    if($Account.sid -cne $Manifest.sid){return 'ACCOUNT_NAME_REUSED_DIFFERENT_SID'}
    'ACCOUNT_AND_MANIFEST_SID_MATCH_REVIEW_REQUIRED'
}
if($LibraryOnly){return}
$c=Get-PaytmAccountContract;$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$stream=$null
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';readOnly=$true;
    account=$null;paths=[ordered]@{};manifest=$null;agent=$null;profile=$null;
    relation=$null;checks=@();failureCount=0;elapsedSeconds=0;
    accountOrServiceChangesPerformed=$false;permissionsChanged=$false;filesDeleted=$false;
    keyContentsRead=$false;credentialsRequested=$false;vpsContacted=$false;ordersEnabled=$false}
function Save-RecoveryReport {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12))
    $stream.Position=0;$stream.SetLength(0);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
}
function Recovery-Check([string]$Name,[int]$Percent,[scriptblock]$Action) {
    Write-Host "[$Percent%] $Name (read-only)"
    Write-Progress -Activity 'Gateway deleted-account recovery inventory' -Status $Name -PercentComplete $Percent
    try{&$Action;$report.checks+=@([pscustomobject]@{name=$Name;captured=$true})}
    catch{$report.failureCount++;$report.checks+=@([pscustomobject]@{name=$Name;captured=$false;errorType=$_.Exception.GetType().Name;hresult=$_.Exception.HResult})}
    Save-RecoveryReport
}
$null=Assert-PaytmAccountPath $OutputDirectory
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-gateway-recovery-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-RecoveryReport
    Recovery-Check 'Account identity' 10 {
        Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
        $account=@(Get-LocalUser -ErrorAction Stop|Where-Object {$_.Name -ieq $c.name})
        if($account.Count -gt 1){throw 'RECOVERY_ACCOUNT_AMBIGUOUS'}
        if($account.Count){$report.account=[pscustomobject]@{sid=$account[0].SID.Value;enabled=$account[0].Enabled;descriptionMatches=($account[0].Description -ceq $c.description)}}
    }
    Recovery-Check 'Installation folder ACL' 25 {$report.paths.root=Get-PaytmRecoveryPath $c.root $true}
    Recovery-Check 'Work folder ACL' 40 {$report.paths.work=Get-PaytmRecoveryPath (Join-Path $c.root 'work') $true}
    Recovery-Check 'Manifest metadata and ACL' 55 {
        $p=Join-Path $c.root 'installation.json';$report.paths.manifest=Get-PaytmRecoveryPath $p $false
        if($report.paths.manifest.exists){$report.manifest=Read-PaytmRecoveryManifest $p}
    }
    Recovery-Check 'Existing agent service' 70 {
        $service=Get-Service -Name ssh-agent -ErrorAction Stop
        $config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ssh-agent' -ErrorAction Stop
        $report.agent=[pscustomobject]@{state=[string]$service.Status;startMode=[string]$service.StartType;
            expectedImage=([string]$config.ImagePath).Trim('"') -ieq $c.agentImage;localSystem=($config.ObjectName -ieq 'LocalSystem')}
    }
    Recovery-Check 'Old SID profile metadata' 85 {
        if($null -ne $report.manifest){
            $profiles=@(Get-CimInstance Win32_UserProfile -Filter ("SID='"+$report.manifest.sid+"'") -OperationTimeoutSec 10 -ErrorAction Stop)
            $report.profile=[pscustomobject]@{count=$profiles.Count;loaded=@($profiles|Where-Object {$_.Loaded}).Count;special=@($profiles|Where-Object {$_.Special}).Count}
        }else{$report.profile=[pscustomobject]@{notAssessed='MANIFEST_SID_UNAVAILABLE'}}
    }
    $report.relation=if(@($report.checks|Where-Object {$_.name -ceq 'Account identity' -and -not $_.captured}).Count){'ACCOUNT_QUERY_FAILED_NOT_PROOF_OF_ABSENCE'}else{Get-PaytmRecoveryRelation $report.account $report.manifest}
    $report.status=if($report.failureCount){'PARTIAL_INVENTORY_RECOVERY_BLOCKED'}else{'INVENTORY_CAPTURED_RECOVERY_REVIEW_REQUIRED'}
}finally{
    $timer.Stop();if($null -ne $stream){try{Save-RecoveryReport}finally{$stream.Dispose()}}
    Write-Progress -Activity 'Gateway deleted-account recovery inventory' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'Do not run Apply/Verify, recreate the account, delete storage or change the shared agent until this inventory is reviewed.'
}
