#Requires -Version 5.1
[CmdletBinding()]param([switch]$LibraryOnly)
$ErrorActionPreference='Stop'
function Get-PaytmConnectivityEvents {
    # The incident window is fixed in UTC. Do not collect messages, SSIDs,
    # addresses, command lines, user names or arbitrary event payloads.
    $from=[DateTimeOffset]::Parse('2026-11-13T06:20:00Z').UtcDateTime
    $to=[DateTimeOffset]::Parse('2026-11-13T06:29:00Z').UtcDateTime
    foreach($spec in @(
        @{log='System';provider='Microsoft-Windows-Kernel-Power';ids=@(42,107,506,507)},
        @{log='System';provider='Microsoft-Windows-Power-Troubleshooter';ids=@(1)},
        @{log='Microsoft-Windows-WLAN-AutoConfig/Operational';provider='Microsoft-Windows-WLAN-AutoConfig';ids=@(8000,8001,8002,8003)},
        @{log='Microsoft-Windows-NetworkProfile/Operational';provider='Microsoft-Windows-NetworkProfile';ids=@(10000,10001)})){
        $row=[ordered]@{channel=$spec.log;provider=$spec.provider;enabled=$null;querySucceeded=$false;limitReached=$false;errorType=$null;events=@()}
        try{
            $log=Get-WinEvent -ListLog $spec.log -ErrorAction Stop
            $row.enabled=[bool]$log.IsEnabled
            if($row.enabled){
                $queryErrors=@()
                $events=@(Get-WinEvent -FilterHashtable @{LogName=$spec.log;ProviderName=$spec.provider;Id=$spec.ids;StartTime=$from;EndTime=$to} -MaxEvents 32 -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
                $bad=@($queryErrors|Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*'})
                if($bad.Count){$row.errorType=$bad[0].Exception.GetBaseException().GetType().Name}
                else{$row.querySucceeded=$true}
                $row.limitReached=$events.Count -eq 32
                $row.events=@($events|ForEach-Object {@{id=[int]$_.Id;recordId=[long]$_.RecordId;utc=$_.TimeCreated.ToUniversalTime().ToString('o')}})
            }
        }catch{$row.errorType=$_.Exception.GetBaseException().GetType().Name}
        [pscustomobject]$row
    }
}
if($LibraryOnly){return}
@{version=1;windowStart='2026-11-13T06:20:00Z';windowEnd='2026-11-13T06:29:00Z';channels=@(Get-PaytmConnectivityEvents)}|ConvertTo-Json -Depth 6 -Compress
