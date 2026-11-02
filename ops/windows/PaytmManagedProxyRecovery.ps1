#Requires -Version 7.0
function Get-PaytmManagedRecoveryPayload([string]$OriginalRun,[string]$RecoveryRun){
 if($OriginalRun -cnotmatch '^[a-f0-9]{32}$' -or $RecoveryRun -cnotmatch '^[a-f0-9]{32}$'){throw 'RECOVERY_RUN_INVALID'}
 $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\ReadPaytmManagedProxyReport.sh')).Replace("`r`n","`n")
 New-TunnelFileLauncher ($body+"`nmr_main '$OriginalRun' '$RecoveryRun'`n")
}
function Read-PaytmManagedRecoveryReport([string]$Text,[string]$OriginalRun,[string]$RecoveryRun){
 if($OriginalRun -cnotmatch '^[a-f0-9]{32}$' -or $RecoveryRun -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 65536){throw 'RECOVERY_REPORT_BOUNDARY'}
 $pattern='(?m)^BEGIN_MANAGED_RECOVERY_'+$RecoveryRun+'\r?\nSTATUS=(CAPTURED|LOG_MATCH_REVIEW)\r?\nLOG_MATCH_COUNT=([0-9]{1,3})\r?\nORIGINAL_RUN='+$OriginalRun+'\r?\nREPORT_BASE64=([A-Za-z0-9+/=]*)\r?\nSNAPSHOT_BASE64=([A-Za-z0-9+/=]*)\r?\nEND_MANAGED_RECOVERY_'+$RecoveryRun+'\r?$'
 $blocks=[regex]::Matches($Text,$pattern);if($blocks.Count -ne 1){throw 'RECOVERY_REPORT_MISSING_OR_DUPLICATE'}
 $m=$blocks[0];$utf8=[Text.UTF8Encoding]::new($false,$true)
 try{$original=$utf8.GetString([Convert]::FromBase64String($m.Groups[3].Value));$snapshot=$utf8.GetString([Convert]::FromBase64String($m.Groups[4].Value))}catch{throw 'RECOVERY_ENCODING_INVALID'}
 if($original.Length -gt 16384 -or $snapshot.Length -gt 16384){throw 'RECOVERY_CONTENT_TOO_LARGE'}
 [pscustomobject]@{status=$m.Groups[1].Value;logMatchCount=[int]$m.Groups[2].Value;originalReport=$original;currentServiceSnapshot=$snapshot}
}
