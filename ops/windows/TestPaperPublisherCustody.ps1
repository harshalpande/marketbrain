#Requires -Version 7.0
# Real same-user Windows DPAPI/ACL checks in a uniquely named temporary directory only.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperPublisherCustody.ps1')
$script:checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function Reject([scriptblock]$action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $message}
$root=Join-Path ([IO.Path]::GetTempPath()) ('publisher-custody-test-'+[guid]::NewGuid().ToString('N'))
$hash='A'*64;$file=Join-Path $root 'publisher.dpapi';$held=$null;$cipher=$null;$plain=$null
try {
    $r=Initialize-PaperPublisherCustody $root $hash
    Check ($r.custodyCreated -and $r.custodyVerified -and $r.custodyRetained) 'initial custody'
    Assert-PaperPrivateAcl $root;Assert-PaperPrivateAcl $file;Check $true 'private ACLs'
    $original=(Get-FileHash $file).Hash
    $r=Initialize-PaperPublisherCustody $root $hash
    Check (-not $r.custodyCreated -and $r.custodyVerified) 'existing custody reused'
    Check ((Get-FileHash $file).Hash -ceq $original) 'no ciphertext rotation'
    $entropy=Get-PaperPublisherEntropy $hash;$plain=Read-PaperCredential $file $entropy
    Check ($plain.Length -eq 48) 'password and salt envelope length'
    Check ((New-PaperCredentialVerifier $plain) -cmatch '^SCRAM-SHA-256\$4096:') 'compatible with future disabled-password staging'
    Reject {Initialize-PaperPublisherCustody $root ('B'*64)} 'different installation binding refused'
    Check ((Get-FileHash $file).Hash -ceq $original) 'binding failure preserves envelope'
    Reject {Read-PaperWriterCustody $file} 'existing writer purpose cannot decrypt publisher'
    $held=[IO.File]::Open((Join-Path $root 'credential.lock'),'Open','ReadWrite','None')
    Reject {Initialize-PaperPublisherCustody $root $hash} 'concurrent custody refused';$held.Dispose();$held=$null
    $cipher=[IO.File]::ReadAllBytes($file);[IO.File]::WriteAllBytes($file,[byte[]]@(1,2,3))
    Reject {Initialize-PaperPublisherCustody $root $hash} 'partial file never regenerated'
    Check ((Get-Item $file).Length -eq 3) 'partial file retained'
    [IO.File]::WriteAllBytes($file,$cipher)
    Check ((Initialize-PaperPublisherCustody $root $hash).custodyVerified) 'restored fixture verified'
    Reject {Get-PaperPublisherEntropy 'invalid'} 'invalid binding refused'
    Write-Host "PASS: $script:checks real Windows custody assertions. No database, Docker, broker or production secret access."
}finally{
    if($held){$held.Dispose()};foreach($buffer in @($cipher,$plain)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
    # Only the two known fixture files and their verified unique directory are removed, never recursively.
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($root) -match '^publisher-custody-test-[a-f0-9]{32}$') {
        foreach($name in @('publisher.dpapi','credential.lock')){Remove-Item -LiteralPath (Join-Path $root $name) -Force -ErrorAction SilentlyContinue}
        Remove-Item -LiteralPath $root -ErrorAction SilentlyContinue
    }
}
