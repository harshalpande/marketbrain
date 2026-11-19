#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1'))))
$checks=0
foreach($case in @(
    @($false,56,'403|0|000',$true,'EXPECTED_DENIAL'),
    @($false,7,'403|0|000',$true,'EXPECTED_DENIAL'),
    @($true,28,'000|0|000',$false,'TIMEOUT_NOT_VERIFIED'),
    @($false,28,'403|0|000',$false,'TIMEOUT_NOT_VERIFIED'),
    @($false,0,'200|0|200',$false,'UNEXPECTED_ALLOWED_RESPONSE'),
    @($false,56,'secret arbitrary raw response',$false,'UNPARSEABLE_RESPONSE'),
    @($false,56,'000|0|000',$false,'UNEXPECTED_RESPONSE')
)) {
    $script:r=[pscustomobject]@{TimedOut=$case[0];ExitCode=$case[1];Output=$case[2]}
    function Invoke-PaytmTransportCurl($Url){if($Url -eq 'http://developer.paytmmoney.com/'){return [pscustomobject]@{TimedOut=$false;ExitCode=0;Output='000|0|403'}};return $script:r}
    $report=[ordered]@{};$passed=$true
    try{Assert-PaytmTransportDenials $report}catch{if($_.Exception.Message -ne 'TRANSPORT_DENIAL_FAILED'){throw};$passed=$false}
    if($passed -ne $case[3]){throw 'Denial acceptance changed'}
    if(-not $passed -and ($report.firstDenialFailure.classification -ne $case[4] -or $report.lastDenialObservation.case -ne 'WRONG_HOST')){throw 'Failure cause not preserved'}
    if(($report|ConvertTo-Json -Depth 6) -match 'secret arbitrary'){throw 'Raw response leaked'}
    $checks++
}
# Third-case failure and immutable first failure.
function Invoke-PaytmTransportCurl($Url){if($Url.StartsWith('http:')){return [pscustomobject]@{TimedOut=$false;ExitCode=0;Output='000|0|200'}};[pscustomobject]@{TimedOut=$false;ExitCode=56;Output='403|0|000'}}
$report=[ordered]@{};try{Assert-PaytmTransportDenials $report;throw 'Allowed plain HTTP passed'}catch{if($_.Exception.Message -ne 'TRANSPORT_DENIAL_FAILED'){throw}}
if($report.firstDenialFailure.case -ne 'PLAIN_HTTP'){throw 'Wrong failed case'}
Save-PaytmDenialObservation $report 'WRONG_PORT' ([pscustomobject]@{TimedOut=$true;ExitCode=28;Output='000|0|000'}) $false
if($report.firstDenialFailure.case -ne 'PLAIN_HTTP' -or $report.lastDenialObservation.case -ne 'WRONG_PORT'){throw 'First cause overwritten'}
Write-Host "DENIAL_EVIDENCE_PASSED: $checks classification/acceptance cases, plain HTTP case, first cause preservation, no raw response."
