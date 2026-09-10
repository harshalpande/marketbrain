param(
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:8080/api/v1/whatsapp'

$boundary = Invoke-RestMethod -Method Get -Uri "$baseUrl/status"
if (-not $boundary.enabled -or
    -not $boundary.sandboxMode -or
    -not $boundary.testAlertsEnabled -or
    -not $boundary.webhookConfigured -or
    -not $boundary.outboundConfigured -or
    $boundary.actionExecutionEnabled -or
    $boundary.executionMode -ne 'PAPER') {
    throw 'The WhatsApp sandbox test boundary is not ready or is not safely restricted to PAPER mode.'
}

Write-Host 'Sending one WhatsApp PAPER-mode interactive test alert...'
try {
    $sent = Invoke-RestMethod -Method Post -Uri "$baseUrl/test-alert"
}
catch {
    throw 'The sandbox alert was not accepted by Meta. Confirm the temporary token is current and that your reply opened the 24-hour test conversation window.'
}

if ($sent.status -ne 'SENT' -or
    $sent.actionExecutionEnabled -or
    $sent.executionMode -ne 'PAPER' -or
    $sent.actions.Count -ne 3) {
    throw 'The WhatsApp sandbox alert did not reach every safe send checkpoint.'
}

Write-Host "Alert sent. On WhatsApp, press APPROVE, REJECT, or DETAILS within $TimeoutSeconds seconds."
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$current = $sent
do {
    Start-Sleep -Seconds 2
    $current = Invoke-RestMethod -Method Get -Uri "$baseUrl/test-alert/$($sent.alertId)"
} while ($current.processedActionCount -eq 0 -and (Get-Date) -lt $deadline)

if ($current.processedActionCount -eq 0) {
    throw 'No WhatsApp button reply reached MarketBrain before the test timeout.'
}

$processed = @($current.actions | Where-Object processed)
if ($processed.Count -ne 1 -or
    $current.actionExecutionEnabled -or
    $current.executionMode -ne 'PAPER') {
    throw 'The WhatsApp action audit did not remain inside the expected non-trading boundary.'
}

[pscustomobject]@{
    status                   = 'COMPLETED'
    alertId                  = $current.alertId
    selectedAction           = $processed[0].action
    processingResult         = $processed[0].result
    processedActionCount     = $current.processedActionCount
    actionExecutionEnabled   = $current.actionExecutionEnabled
    executionMode            = $current.executionMode
    signalCreated            = $false
    paperFillCreated         = $false
    brokerOrderCreated       = $false
}

Write-Host ''
Write-Host 'WHATSAPP SANDBOX TEST COMPLETE: the signed, allow-listed, one-time button reply was audited.'
Write-Host 'No signal, PAPER fill, broker order, or live trading action was created.'
