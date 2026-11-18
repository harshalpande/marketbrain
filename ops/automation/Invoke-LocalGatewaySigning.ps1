#requires -Version 7.2
# Password-dependent step remains local. The automation diagnostic retrieves
# only allowlisted fields from the completed existing signing test.
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell 7 as Administrator for this password-dependent test.' }
} finally { $identity.Dispose() }
$directory=Join-Path 'C:\MarketBrainData\Review' ('automation-signing-'+[guid]::NewGuid().ToString('N'))
$latest='C:\MarketBrainData\Review\automation-gateway-signing-latest.json'
function Get-LocalGatewaySigningState {
    $hashes=[ordered]@{}
    foreach($entry in @(@('supervisor-v1','manifest.json'),@('supervisor-v1','control.json'),@('supervisor-v1','transport-control.json'),@('supervisor-work-v1','status.json'),@('supervisor-work-v1','blocked.json'),@('supervisor-work-v1','startup-failure.json'))) {
        $file=Join-Path ('C:\ProgramData\MarketBrainPaytmGateway\'+$entry[0]) $entry[1]
        $hashes[$entry[1]]=if(Test-Path -LiteralPath $file){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}else{'ABSENT'}
    }
    return ($hashes|ConvertTo-Json -Compress)
}
$before=Get-LocalGatewaySigningState
$result=$null
try {
    & (Join-Path $PSScriptRoot '..\windows\TestPaytmGatewayScheduledSigning.ps1') -OutputDirectory $directory
} finally {
    $files=@(Get-ChildItem -LiteralPath $directory -Filter 'paytm-scheduled-signing-*.json' -ErrorAction SilentlyContinue)
    if ($files.Count -eq 1 -and $files[0].Length -le 65536) {
        $bytes=[IO.File]::ReadAllBytes($files[0].FullName)
        $result=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff) | ConvertFrom-Json -ErrorAction Stop
        if ($result.runId -notmatch '^[a-f0-9]{32}$' -or $result.ordersEnabled -ne $false) { throw 'Signing report contract not accepted; original retained.' }
        $unchanged=$before -ceq (Get-LocalGatewaySigningState)
        $result|Add-Member -NotePropertyName productionStateUnchanged -NotePropertyValue $unchanged -Force
        $result.sourceHashes|Add-Member -NotePropertyName 'Invoke-LocalGatewaySigning.ps1' -NotePropertyValue ((Get-FileHash -LiteralPath $PSCommandPath).Hash) -Force
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 12))
        if($bytes.Length -gt 65536){throw 'Augmented report exceeds collection limit; original retained.'}
        # Original evidence remains untouched; atomic completed-report copy.
        $temporary=$latest+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        [IO.File]::WriteAllBytes($temporary,$bytes)
        [IO.File]::Move($temporary,$latest,$true)
        Write-Host "RESULT_READY_FOR_AUTOMATIC_COLLECTION: $($result.runId) / $($result.status)"
        Write-Host 'Tell the agent the local prompt step is finished. No report upload is needed.'
        if(-not $unchanged){throw 'Gateway state changed during signing test; preserved for review, do not recover automatically.'}
    } else {
        Write-Host 'No single bounded report was produced; preserve the console error and do not rerun automatically.'
    }
}
