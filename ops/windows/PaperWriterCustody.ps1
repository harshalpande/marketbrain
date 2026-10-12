# Definitions only. Not wired to Java, Docker, PostgreSQL or application credentials.
. (Join-Path $PSScriptRoot 'PaperStorageKey.ps1')
Add-Type -AssemblyName System.Security

function Assert-PaperCustodyPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':')){throw 'CUSTODY_LOCAL_ABSOLUTE_PATH_REQUIRED'}
    $full=[IO.Path]::GetFullPath($Path)
    $parent=$full
    while($parent){
        if(Test-Path -LiteralPath $parent){
            if((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'CUSTODY_REPARSE_PATH_REFUSED'}
        }
        $parent=[IO.Path]::GetDirectoryName($parent)
    }
    return $full
}
function Get-PaperCustodyEntropy([string]$Purpose) {
    if($Purpose -cnotmatch '^[A-Z0-9_]{8,80}$'){throw 'CUSTODY_PURPOSE_INVALID'}
    return ,[Text.Encoding]::UTF8.GetBytes('MARKETBRAIN_CURRENT_USER_V1|'+$Purpose)
}
function Save-PaperWriterCustody([string]$Path,[byte[]]$Secret,[string]$Purpose='PAPER_REVIEW_WRITER_V1') {
    $full=Assert-PaperCustodyPath $Path
    $directory=[IO.Path]::GetDirectoryName($full)
    Assert-PaperPrivateAcl $directory
    if($null -eq $Secret -or $Secret.Length -ne 32){throw 'CUSTODY_SECRET_LENGTH_INVALID'}
    $entropy=Get-PaperCustodyEntropy $Purpose; $cipher=$null
    try {
        $cipher=[Security.Cryptography.ProtectedData]::Protect($Secret,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$stream.Write($cipher,0,$cipher.Length);$stream.Flush($true)} finally {$stream.Dispose()}
        Protect-PaperPrivateAcl $full
    }
    finally {if($cipher){[Array]::Clear($cipher,0,$cipher.Length)};[Array]::Clear($entropy,0,$entropy.Length)}
    # Caller owns and must erase Secret. No return value contains secret material.
}
function Read-PaperWriterCustody([string]$Path,[string]$Purpose='PAPER_REVIEW_WRITER_V1') {
    $full=Assert-PaperCustodyPath $Path
    Assert-PaperPrivateAcl ([IO.Path]::GetDirectoryName($full)); Assert-PaperPrivateAcl $full
    $entropy=Get-PaperCustodyEntropy $Purpose; $cipher=$null; $plain=$null
    try {
        $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            if($stream.Length -lt 64 -or $stream.Length -gt 4096){throw 'CUSTODY_BLOB_SIZE_INVALID'}
            $cipher=New-Object byte[] ([int]$stream.Length)
            $offset=0
            while($offset -lt $cipher.Length){$n=$stream.Read($cipher,$offset,$cipher.Length-$offset);if($n -eq 0){throw 'CUSTODY_TRUNCATED'};$offset+=$n}
        } finally {$stream.Dispose()}
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        if($plain.Length -ne 32){[Array]::Clear($plain,0,$plain.Length);throw 'CUSTODY_SECRET_LENGTH_INVALID'}
        return ,$plain
    }
    finally {if($cipher){[Array]::Clear($cipher,0,$cipher.Length)};[Array]::Clear($entropy,0,$entropy.Length)}
}
