# Definitions only. Key contents never enter console output or reports.
function Assert-PaperPrivateAcl([string]$Path) {
    $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $acl=Get-Acl -LiteralPath $Path
    if(-not $acl.AreAccessRulesProtected){throw 'Key directory/file has inherited permissions. Review its private ACL; no automatic repair.'}
    foreach($rule in $acl.Access){
        if($rule.AccessControlType -eq 'Allow'){
            $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if($sid -notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'Key permissions grant another identity access. Review manually.'}
        }
    }
}
function Protect-PaperPrivateAcl([string]$Path,[switch]$Directory) {
    $acl=Get-Acl -LiteralPath $Path;$acl.SetAccessRuleProtection($true,$false)
    foreach($rule in @($acl.Access)){[void]$acl.RemoveAccessRuleSpecific($rule)}
    $inherit=if($Directory){[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'}else{[Security.AccessControl.InheritanceFlags]::None}
    foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18')){
        $identity=[Security.Principal.SecurityIdentifier]::new($sid)
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl',$inherit,'None','Allow');$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
    Assert-PaperPrivateAcl $Path
}
function Initialize-PaperStorageKey([switch]$Create) {
    $directory='C:\MarketBrainData\Secrets\PaperApproval'
    $file=Join-Path $directory 'delivery.key'
    # Resolve all existing parents and reject junctions/symlinks before creating anything.
    foreach($p in @('C:\MarketBrainData','C:\MarketBrainData\Secrets',$directory,$file)){
        if(Test-Path -LiteralPath $p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Key path contains a reparse point.'}}
    }
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
        if(-not $Create){throw 'Key missing. Restore the original key; creation requires explicit first-install approval.'}
        if(-not (Test-Path -LiteralPath $directory)){[void](New-Item -ItemType Directory -Path $directory -Force);Protect-PaperPrivateAcl $directory -Directory}
        Assert-PaperPrivateAcl $directory
        $bytes=New-Object byte[] 32;$encoded=$null;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try{$rng.GetBytes($bytes);$encoded=[Text.Encoding]::ASCII.GetBytes([Convert]::ToBase64String($bytes));$stream=[IO.File]::Open($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($encoded,0,$encoded.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
        finally{$rng.Dispose();[Array]::Clear($bytes,0,$bytes.Length);if($encoded){[Array]::Clear($encoded,0,$encoded.Length)}}
        Protect-PaperPrivateAcl $file
    }
    Assert-PaperPrivateAcl $directory;Assert-PaperPrivateAcl $file
    if((Get-Item -LiteralPath $file).Length -gt 128){throw 'Invalid key file size.'}
    $value=[IO.File]::ReadAllText($file).Trim()
    if($value -cnotmatch '^[A-Za-z0-9+/]{43}=$'){throw 'Invalid key file encoding.'}
    $decoded=[Convert]::FromBase64String($value)
    try{if($decoded.Length -ne 32 -or -not @($decoded|Where-Object {$_ -ne 0}).Count){throw 'Invalid key material.'}}
    finally{[Array]::Clear($decoded,0,$decoded.Length);$value=$null}
    return $file
}
function Assert-PaperStorageStatus($Status) {
    if($Status.version -cne 'PAPER_APPROVAL_STORAGE_V1' -or $Status.status -cne 'STORAGE_KEY_VERIFIED_ACTIONS_DISABLED'){throw 'Application storage/key setup is not verified. Preserve the original key and report; do not regenerate.'}
    foreach($flag in @('databaseWritesPerformed','notificationEnabled','actionExecutionEnabled','liveExecutionEnabled')){if($Status.$flag -isnot [bool] -or $Status.$flag){throw 'Unexpected storage capability or write.'}}
}
