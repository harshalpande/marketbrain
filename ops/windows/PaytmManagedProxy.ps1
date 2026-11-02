#Requires -Version 7.0
function Get-PaytmManagedProxyPayload([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'MANAGED_RUN_INVALID'}
    $parts=@()
    foreach($name in @('InstallPaytmTunnelIdentity.sh','StagePaytmLoopbackProxy.sh','ManagePaytmProxyLifecycle.sh')){
        $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$name")).Replace("`r`n","`n")
        if($name -cne 'ManagePaytmProxyLifecycle.sh'){
            $entry=if($name -ceq 'InstallPaytmTunnelIdentity.sh'){'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then tg_main "$@"; fi'}else{'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then pg_main "$@"; fi'}
            if(-not $body.Contains($entry)){throw 'MANAGED_SOURCE_ENTRY_CHANGED'}
            $body=$body.Replace($entry,'')
        }
        $parts+=$body
    }
    New-TunnelFileLauncher (($parts -join "`n")+"`ngm_main '$RunId'`n")
}
function Read-PaytmManagedProxyReport([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 65536){throw 'MANAGED_REPORT_BOUNDARY'}
    $pattern='(?m)^BEGIN_MANAGED_REPORT_'+$RunId+'\r?\n(?<json>\{[^\r\n]+\})\r?\nEND_MANAGED_REPORT_'+$RunId+'\r?$'
    $matches=[regex]::Matches($Text,$pattern)
    if($matches.Count -ne 1){throw 'MANAGED_REPORT_MISSING_OR_DUPLICATE'}
    $value=$matches[0].Groups['json'].Value|ConvertFrom-Json -ErrorAction Stop
    foreach($field in @('version','exitCode','failureLine','elapsedSeconds','httpStatus')){
        if($value.$field -isnot [int] -and $value.$field -isnot [long]){throw 'MANAGED_REPORT_NUMBER_REQUIRED'}
    }
    if($value.version -ne 1 -or $value.runId -cne $RunId -or $value.stage -cnotmatch '^[A-Z_]{1,60}$' -or $value.exitCode -lt 0 -or $value.exitCode -gt 255){throw 'MANAGED_REPORT_SCHEMA'}
    if($value.elapsedSeconds -lt 0 -or $value.elapsedSeconds -gt 3600 -or $value.failureLine -lt 0 -or $value.failureLine -gt 5000){throw 'MANAGED_REPORT_TIMING'}
    foreach($field in @('success','baselineVerified','backupVerified','effectivePolicyVerified','crashRestartVerified','disableVerified','conditionBlocksStart','tlsVerified','denialsVerified','bootEnabled','finalRunning','cleanupPassed','credentialsUsed','ordersEnabled')){
        if($value.$field -isnot [bool]){throw 'MANAGED_REPORT_BOOLEAN_REQUIRED'}
    }
    if($value.credentialsUsed -or $value.ordersEnabled){throw 'MANAGED_REPORT_SCOPE'}
    $value
}
function Assert-PaytmManagedProxyPassed($Value) {
    if($Value.exitCode -ne 0 -or $Value.stage -cne 'COMPLETE' -or $Value.httpStatus -lt 200 -or $Value.httpStatus -gt 599){throw 'MANAGED_PROXY_NOT_PASSED'}
    foreach($field in @('success','baselineVerified','backupVerified','effectivePolicyVerified','crashRestartVerified','disableVerified','conditionBlocksStart','tlsVerified','denialsVerified','bootEnabled','finalRunning','cleanupPassed')){
        if($Value.$field -isnot [bool] -or -not $Value.$field){throw 'MANAGED_PROXY_PROOF_MISSING'}
    }
    if($Value.credentialsUsed -ne $false -or $Value.ordersEnabled -ne $false){throw 'MANAGED_REPORT_SCOPE'}
}
