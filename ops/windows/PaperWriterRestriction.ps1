# Pure planning functions. No path to the real HBA file and no database access.
function Get-PaperRestrictionHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
}
function New-PaperWriterRestrictionBlock {
    # Physical replication is not matched by the database keyword "all".
    return (@(
        '# BEGIN MARKETBRAIN WRITER RESTRICTION V1'
        'host marketbrain marketbrain_paper_review_writer 127.0.0.1/32 scram-sha-256'
        'local all,replication marketbrain_paper_review_writer reject'
        'host all,replication marketbrain_paper_review_writer 0.0.0.0/0 reject'
        'host all,replication marketbrain_paper_review_writer ::/0 reject'
        '# END MARKETBRAIN WRITER RESTRICTION V1'
    ) -join "`n")+"`n"
}
function New-PaperRestrictionCandidate([byte[]]$Original,[string]$ExpectedHash) {
    if($null -eq $Original -or $Original.Length -eq 0 -or $Original.Length -gt 1MB){throw 'RESTRICTION_INPUT_SIZE'}
    if($ExpectedHash -cnotmatch '^[A-F0-9]{64}$' -or (Get-PaperRestrictionHash $Original) -cne $ExpectedHash){throw 'RESTRICTION_SOURCE_DRIFT'}
    $offset=0
    if($Original.Length -ge 3 -and $Original[0] -eq 239 -and $Original[1] -eq 187 -and $Original[2] -eq 191){$offset=3}
    try {$text=[Text.UTF8Encoding]::new($false,$true).GetString($Original,$offset,$Original.Length-$offset)}catch{throw 'RESTRICTION_ENCODING_UNSUPPORTED'}
    if($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or $text -match '\r(?!\n)'){throw 'RESTRICTION_ENCODING_UNSUPPORTED'}
    if($text -match 'MARKETBRAIN WRITER RESTRICTION|marketbrain_paper_review_writer'){throw 'RESTRICTION_EXISTING_WRITER_BLOCK'}
    # Deliberately small accepted syntax, not a general PostgreSQL parser. Includes,
    # quotes, regexes, auth options, continuations and netmask forms require review.
    foreach($line in ($text -split '\r?\n')){
        if($line -match '\\[ \t]*$'){throw 'RESTRICTION_COMPLEX_LAYOUT'}
        $rule=($line -split '#',2)[0].Trim()
        if(-not $rule){continue}
        $names='[a-zA-Z_][a-zA-Z0-9_]*(?:,[a-zA-Z_][a-zA-Z0-9_]*)*'
        if($rule -cnotmatch ('^(?:local\s+'+$names+'\s+'+$names+'\s+(?:scram-sha-256|reject)|host\s+'+$names+'\s+'+$names+'\s+(?:127\.0\.0\.1/32|::1/128|0\.0\.0\.0/0|::/0)\s+(?:scram-sha-256|reject))$')){throw 'RESTRICTION_COMPLEX_LAYOUT'}
    }
    $block=New-PaperWriterRestrictionBlock
    if($text.Contains("`r`n")){
        if($text.Replace("`r`n",'').Contains("`n")){throw 'RESTRICTION_MIXED_LINE_ENDINGS'}
        $block=$block.Replace("`n","`r`n")
    }
    $prefix=[Text.Encoding]::UTF8.GetBytes($block)
    $result=New-Object byte[] ($Original.Length+$prefix.Length)
    [Array]::Copy($Original,0,$result,0,$offset)
    [Array]::Copy($prefix,0,$result,$offset,$prefix.Length)
    [Array]::Copy($Original,$offset,$result,$offset+$prefix.Length,$Original.Length-$offset)
    return ,$result
}
function Assert-PaperRestrictionRecovery([byte[]]$Backup,[string]$OriginalHash,[byte[]]$Current,[string]$OwnedCurrentHash) {
    if($OriginalHash -cnotmatch '^[A-F0-9]{64}$' -or $OwnedCurrentHash -cnotmatch '^[A-F0-9]{64}$' -or
       (Get-PaperRestrictionHash $Backup) -cne $OriginalHash -or (Get-PaperRestrictionHash $Current) -cne $OwnedCurrentHash){throw 'RESTRICTION_RECOVERY_OWNERSHIP_LOST'}
}
function Read-PaperRestrictionEvidence([string]$Path,[string]$ExpectedHash) {
    if((Get-Item -LiteralPath $Path).Length -gt 2MB){throw 'RESTRICTION_EVIDENCE_SIZE'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    if((Get-PaperRestrictionHash $bytes) -cne $ExpectedHash){throw 'RESTRICTION_EVIDENCE_HASH_MISMATCH'}
    $v=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json
    if($v.version -cne 'PAPER_WRITER_ACCESS_V1' -or $v.status -cne 'ACCESS_EVIDENCE_CAPTURED_REVIEW_REQUIRED' -or $v.validationStage -cne 'COMPLETE' -or
       $v.failureCode -or $v.cleanupFailureCode -or $v.diagnosticCleanupComplete -isnot [bool] -or -not $v.diagnosticCleanupComplete){throw 'RESTRICTION_EVIDENCE_INCOMPLETE'}
    foreach($flag in @('writerLoginAttempted','configurationChanged','databaseWritesPerformed','credentialsSaved','applicationWriterActivated','actionExecutionEnabled')){
        if($v.$flag -isnot [bool] -or $v.$flag){throw 'RESTRICTION_EVIDENCE_UNSAFE'}
    }
    Assert-PaperApplicationRoute $v.route $v.inventory $v.serverMetadata $v.runId
    if($v.route.database -cne 'marketbrain' -or $v.route.serverPort -ne 5432 -or $v.route.clientAddress -cne '127.0.0.1' -or $v.inventory.writerLoginEnabled -isnot [bool] -or $v.inventory.writerLoginEnabled){throw 'RESTRICTION_SCOPE_NOT_APPROVED'}
    $fw=Read-PaperFirewallOutput ($v.firewall|ConvertTo-Json -Depth 12 -Compress) $false
    if($fw.status -cne 'METADATA_CAPTURED_REVIEW_REQUIRED'){throw 'RESTRICTION_FIREWALL_INCOMPLETE'}
    return $v
}
