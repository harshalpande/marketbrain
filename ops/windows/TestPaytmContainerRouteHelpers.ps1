#Requires -Version 5.1
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmContainerRoute.ps1')
$checks=0
function Check([bool]$Value){if(-not $Value){throw 'Route helper contract failed'};$script:checks++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed}
function Observation {
    [pscustomobject]@{version='PAYTM_CONTAINER_ROUTE_V1';proxyHost='host.docker.internal';proxyPort=18889;applicationProcessVerified=$false;credentialsUsed=$false;ordersEnabled=$false;elapsedMillis=3;status='TLS_RESPONSE';httpStatus=503;tlsVerified=$true;failureType='NONE'}
}
$value=Observation
Assert-PaytmRouteObservation $value $true; $checks++
Reject {Assert-PaytmRouteObservation $value $false}
foreach($property in @('credentialsUsed','ordersEnabled','applicationProcessVerified')){
    $value=Observation; $value.$property=$true; Reject {Assert-PaytmRouteObservation $value $true}
}
$value=Observation; $value.tlsVerified='true'; Reject {Assert-PaytmRouteObservation $value $true}
$value=Observation; $value.proxyHost='127.0.0.1'; Reject {Assert-PaytmRouteObservation $value $true}
$value=Observation; $value.proxyPort=22; Reject {Assert-PaytmRouteObservation $value $true}
$value=Observation; $value.httpStatus=0; Reject {Assert-PaytmRouteObservation $value $true}
$value=Observation; $value.status='TRANSPORT_FAILED'; $value.httpStatus=0; $value.tlsVerified=$false; $value.failureType='ConnectException'
Assert-PaytmRouteObservation $value $false; $checks++
Reject {Assert-PaytmRouteObservation $value $true}
foreach($failure in @('NONE','INTERRUPTED','NO_TLS_SESSION','UnexpectedException')){$value.failureType=$failure;Reject {Assert-PaytmRouteObservation $value $false}}
$route=[ordered]@{Docker='fixture';Root='C:\Users\Owner With Spaces\marketbrain'}
$script:fixtureIdentity=('a'*64)+'|true|fixture-start|sha256:fixture|marketbrain-service|'+$route.Root
function Invoke-RouteCommand {param($Label,$Executable,$Arguments,$Limit) [pscustomobject]@{Stdout=$script:fixtureIdentity}}
$identity=Get-PaytmContainerIdentity ('a'*12)
Check ($identity.id -eq ('a'*64))
Reject {Get-PaytmContainerIdentity 'bad; command'}
$script:fixtureIdentity=$script:fixtureIdentity.Replace('|true|','|false|'); Reject {Get-PaytmContainerIdentity ('a'*12)}
$script:fixtureIdentity=$script:fixtureIdentity.Replace('|false|','|true|').Replace('|marketbrain-service|','|different-service|'); Reject {Get-PaytmContainerIdentity ('a'*12)}
$script:fixtureIdentity=$script:fixtureIdentity.Replace('|different-service|','|marketbrain-service|').Replace($route.Root,'C:\other'); Reject {Get-PaytmContainerIdentity ('a'*12)}
Write-Host "PASS: $checks route observation and container identity helper assertions. No Docker or VPS calls."
