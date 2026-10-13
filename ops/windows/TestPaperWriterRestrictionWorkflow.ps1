# Offline only. Fresh synthetic directory, no user-supplied file targets.
[CmdletBinding()]param([switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Ok,[string]$Name){if(-not $Ok){throw ('RESTRICTION_TEST_FAILED_'+$Name)};$checks.Add($Name)}
function Denied([scriptblock]$Action,[string]$Code,[string]$Name){$caught=$null;try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Check ($caught -ceq $Code) $Name}
$timer=[Diagnostics.Stopwatch]::StartNew()
$originalText="# synthetic fixture only`nlocal all all scram-sha-256`nhost all all 127.0.0.1/32 scram-sha-256`nhost all all ::1/128 scram-sha-256`n"
$bytes=[Text.Encoding]::UTF8.GetBytes($originalText);$hash=Get-PaperRestrictionHash $bytes
$candidate=New-PaperRestrictionCandidate $bytes $hash
$block=New-PaperWriterRestrictionBlock
Check ([Text.Encoding]::UTF8.GetString($candidate) -ceq ($block+$originalText)) 'prefix_and_non_target_preserved'
# Independent fixed-format policy oracle over the emitted lines; not a live auth test.
function Match-FixtureRule([string]$User,[string]$Database,[string]$Address,[bool]$Local=$false){
    foreach($line in ([Text.Encoding]::UTF8.GetString($candidate) -split '\r?\n')){
        if(-not $line -or $line.StartsWith('#')){continue};$p=$line -split '\s+'
        if(($p[0] -ceq 'local') -ne $Local){continue}
        if($p[2] -cne 'all' -and $p[2] -cne $User){continue}
        $dbs=$p[1].Split(',');if($dbs -cnotcontains $Database -and -not($Database -cne 'replication' -and $dbs -ccontains 'all')){continue}
        if($Local){return $p[3]}
        $ip=[Net.IPAddress]::Parse($Address);$ipv4=$ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
        if(($p[3] -ceq '0.0.0.0/0' -and $ipv4) -or ($p[3] -ceq '::/0' -and -not $ipv4) -or $p[3] -ceq ($Address+$(if($ipv4){'/32'}else{'/128'}))){return $p[4]}
    };return 'NO_MATCH'
}
$writer='marketbrain_paper_review_writer'
Check ((Match-FixtureRule $writer 'marketbrain' '127.0.0.1') -ceq 'scram-sha-256') 'writer_loopback_allow'
foreach($db in @('postgres','template1','other','replication')){Check ((Match-FixtureRule $writer $db '127.0.0.1') -ceq 'reject') ('writer_deny_'+$db)}
foreach($address in @('127.0.0.2','192.168.1.2','::1','::ffff:127.0.0.1','2001:db8::1')){Check ((Match-FixtureRule $writer 'marketbrain' $address) -ceq 'reject') ('writer_deny_source_'+$address)}
foreach($db in @('marketbrain','replication')){Check ((Match-FixtureRule $writer $db '' $true) -ceq 'reject') ('socket_deny_'+$db)}
foreach($user in @('marketbrain_app','postgres','marketbrain_paper_review_writer_other')){Check ((Match-FixtureRule $user 'marketbrain' '127.0.0.1') -ceq 'scram-sha-256') ('non_target_'+$user)}
foreach($newline in @("`n","`r`n")){
    foreach($bom in @($false,$true)){
        $body=[Text.Encoding]::UTF8.GetBytes($originalText.Replace("`n",$newline));if($bom){$body=[byte[]](@(239,187,191)+$body)}
        $proposed=New-PaperRestrictionCandidate $body (Get-PaperRestrictionHash $body)
        $remove=[Text.Encoding]::UTF8.GetByteCount($block.Replace("`n",$newline));$skip=if($bom){3}else{0}
        $restored=New-Object byte[] $body.Length;[Array]::Copy($proposed,0,$restored,0,$skip);[Array]::Copy($proposed,$skip+$remove,$restored,$skip,$body.Length-$skip)
        Check ((Get-PaperRestrictionHash $restored) -ceq (Get-PaperRestrictionHash $body)) ('byte_preservation_'+$newline.Length+'_'+$bom)
    }
}
Denied {New-PaperRestrictionCandidate $bytes ('0'*64)} 'RESTRICTION_SOURCE_DRIFT' 'stale_source'
Denied {New-PaperRestrictionCandidate $candidate (Get-PaperRestrictionHash $candidate)} 'RESTRICTION_EXISTING_WRITER_BLOCK' 'duplicate_block'
foreach($bad in @('include other.conf','include_if_exists other.conf','include_dir other','host all all all trust','host all all 127.0.0.1 255.255.255.255 scram-sha-256','host "quoted" all 127.0.0.1/32 reject','local all, all reject','malformed','# continued\')){
    $b=[Text.Encoding]::UTF8.GetBytes($bad);Denied {New-PaperRestrictionCandidate $b (Get-PaperRestrictionHash $b)} 'RESTRICTION_COMPLEX_LAYOUT' ('reject_layout_'+$checks.Count)
}
$b=[byte[]]@(255,254,0,0);Denied {New-PaperRestrictionCandidate $b (Get-PaperRestrictionHash $b)} 'RESTRICTION_ENCODING_UNSUPPORTED' 'reject_utf16'
$b=[Text.Encoding]::UTF8.GetBytes("# one`r`n# two`n");Denied {New-PaperRestrictionCandidate $b (Get-PaperRestrictionHash $b)} 'RESTRICTION_MIXED_LINE_ENDINGS' 'mixed_newlines'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('mb-restriction-fixture-'+[Guid]::NewGuid().ToString('N'))
$clean=$false
try {
    [void][IO.Directory]::CreateDirectory($sandbox)
    if((Get-Item -LiteralPath $sandbox).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RESTRICTION_FIXTURE_REPARSE'}
    $target=Join-Path $sandbox 'synthetic.conf';$backup=Join-Path $sandbox 'backup.fixture';$stage=Join-Path $sandbox 'stage.fixture'
    [IO.File]::WriteAllBytes($target,$bytes)
    [IO.File]::WriteAllBytes($stage,[byte[]]@(35,32)) # interruption before replace leaves original intact
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($target))) -ceq $hash) 'partial_stage_preserves_original'
    [IO.File]::WriteAllBytes($stage,$candidate)
    [IO.File]::Replace($stage,$target,$backup)
    $owned=Get-PaperRestrictionHash $candidate
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($backup))) -ceq $hash) 'backup_original_bytes'
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($target))) -ceq $owned) 'atomic_replacement_readback'
    Assert-PaperRestrictionRecovery ([IO.File]::ReadAllBytes($backup)) $hash ([IO.File]::ReadAllBytes($target)) $owned
    $edited=[Text.Encoding]::UTF8.GetBytes('# concurrent edit');[IO.File]::WriteAllBytes($target,$edited)
    Denied {Assert-PaperRestrictionRecovery $bytes $hash ([IO.File]::ReadAllBytes($target)) $owned} 'RESTRICTION_RECOVERY_OWNERSHIP_LOST' 'concurrent_edit_not_overwritten'
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($target))) -ceq (Get-PaperRestrictionHash $edited)) 'concurrent_bytes_preserved'
    Denied {Assert-PaperRestrictionRecovery $edited $hash $candidate $owned} 'RESTRICTION_RECOVERY_OWNERSHIP_LOST' 'tampered_backup_denied'
    [IO.File]::WriteAllBytes($target,$candidate)
    Assert-PaperRestrictionRecovery ([IO.File]::ReadAllBytes($backup)) $hash ([IO.File]::ReadAllBytes($target)) $owned
    [IO.File]::WriteAllBytes($stage,[IO.File]::ReadAllBytes($backup));[IO.File]::Replace($stage,$target,(Join-Path $sandbox 'replaced.fixture'))
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($target))) -ceq $hash) 'rollback_original_bytes'
} finally {
    # Exact generated fixture only. Never recursive and never a user-provided target.
    foreach($name in @('synthetic.conf','backup.fixture','stage.fixture','replaced.fixture')){[IO.File]::Delete((Join-Path $sandbox $name))}
    [IO.Directory]::Delete($sandbox,$false);$clean=$true
}
$result=[pscustomobject]@{version='PAPER_RESTRICTION_TESTS_V1';status='PASSED';checks=$checks.ToArray();checkCount=$checks.Count;elapsedSeconds=$timer.Elapsed.TotalSeconds;fixtureCleanupComplete=$clean;postgresAuthenticationTested=$false;realHbaTouched=$false}
if($PassThru){$result}else{Write-Host "PASS: $($checks.Count) restriction assertions; synthetic files only; elapsed=$($timer.Elapsed.TotalSeconds)s"}
