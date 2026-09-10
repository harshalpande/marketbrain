param(
    [string]$BaseUrl = 'http://127.0.0.1:8080'
)

$ErrorActionPreference = 'Stop'

$health = Invoke-RestMethod -Uri "$BaseUrl/actuator/health" -TimeoutSec 60
if ($health.status -ne 'UP') {
    throw 'MarketBrain health is not UP.'
}

$status = Invoke-RestMethod -Uri "$BaseUrl/api/v1/notifications/status" -TimeoutSec 60
if (-not $status.dualDeliveryReady -or
    -not $status.testEnabled -or
    $status.messageParity -ne 'EXACT_SHARED_TEXT' -or
    -not $status.perChannelIdempotency -or
    -not $status.failureIsolation -or
    $status.actionExecutionEnabled) {
    throw 'The governed dual-notification test boundary is not ready.'
}

$testId = [guid]::NewGuid()
Write-Host 'Sending one identical PAPER-mode system NOTE to Telegram and WhatsApp...'
$result = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/api/v1/notifications/test-note?testId=$testId" `
    -TimeoutSec 60

$channels = @($result.channels)
if ($result.status -ne 'COMPLETED' -or
    $channels.Count -ne 2 -or
    @($channels | Where-Object status -ne 'SENT').Count -ne 0 -or
    $result.actionExecutionEnabled) {
    $result | Format-List *
    throw 'The identical dual-channel notification was not delivered through both channels.'
}

[pscustomobject]@{
    status                   = $result.status
    testId                   = $result.testId
    messageHash              = $result.messageHash
    telegramStatus           = ($channels | Where-Object channel -eq 'TELEGRAM').status
    whatsAppStatus           = ($channels | Where-Object channel -eq 'WHATSAPP').status
    messageParity            = $status.messageParity
    perChannelIdempotency    = $status.perChannelIdempotency
    failureIsolation         = $status.failureIsolation
    actionExecutionEnabled   = $result.actionExecutionEnabled
}

Write-Host ''
Write-Host 'DUAL NOTIFICATION TEST COMPLETE: Telegram and WhatsApp received the same message body.'
Write-Host 'No signal, PAPER fill, broker order, or live trading action was created.'
