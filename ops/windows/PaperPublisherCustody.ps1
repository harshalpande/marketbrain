# Definitions only. Reuse the established 48-byte DPAPI envelope and private ACL helpers.
. (Join-Path $PSScriptRoot 'PaperWriterCredential.ps1')
function Get-PaperPublisherEntropy([string]$InstallationHash) {
    if($InstallationHash -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'PUBLISHER_INSTALLATION_HASH_INVALID'}
    return ,[Text.Encoding]::UTF8.GetBytes('PAPER_PUBLISHER_CREDENTIAL_V1|marketbrain-paper-publisher|'+$InstallationHash.ToUpperInvariant())
}
function Initialize-PaperPublisherCustody([string]$Directory,[string]$InstallationHash) {
    $directory=Assert-PaperCustodyPath $Directory
    $path=Assert-PaperCustodyPath (Join-Path $directory 'publisher.dpapi')
    $entropy=Get-PaperPublisherEntropy $InstallationHash
    $lock=$null;$payload=$null;$readback=$null;$created=$false
    try {
        if(-not(Test-Path -LiteralPath $directory)){[void](New-Item -ItemType Directory -Path $directory);Protect-PaperHbaBackupAcl $directory -Directory}
        Assert-PaperPrivateAcl $directory
        $lockPath=Assert-PaperCustodyPath (Join-Path $directory 'credential.lock')
        $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
        if(Test-Path -LiteralPath $path){$payload=Read-PaperCredential $path $entropy}
        else {
            $payload=New-Object byte[] 48
            $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
            try{$rng.GetBytes($payload)}finally{$rng.Dispose()}
            Save-PaperCredential $path $payload $entropy;$created=$true
        }
        $readback=Read-PaperCredential $path $entropy
        $difference=0;for($i=0;$i -lt 48;$i++){$difference=$difference -bor ($payload[$i] -bxor $readback[$i])}
        if($difference -ne 0){throw 'PUBLISHER_CUSTODY_READBACK_MISMATCH'}
        return @{custodyCreated=$created;custodyVerified=$true;custodyRetained=$true}
    }finally {
        foreach($buffer in @($payload,$readback,$entropy)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
        if($lock){$lock.Dispose()}
    }
}
