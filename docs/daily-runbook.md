# MarketBrain daily runbook

This is the single operational guide for building, running, checking, and stopping MarketBrain. It is maintained with every deployable change.

## Safety boundary

- MarketBrain is currently **PAPER MODE only**. The application creates no real broker orders.
- Never commit `.env`, credentials, access tokens, passwords, or OTPs.
- Telegram uses outbound long polling and one private paired identity. Never commit or paste its bot token or pairing code into source files, Git, logs, or chat.
- PostgreSQL and Ollama run natively on the spare Windows laptop. Docker runs only the MarketBrain backend and dashboard.
- Docker publishes both services on Windows `127.0.0.1` only. The backend listens on `0.0.0.0` only inside its isolated container so Docker port forwarding works; it is not publicly exposed and is not yet available from another device over Tailscale.

## Two-machine workflow

| Machine | Purpose | What to run there |
| --- | --- | --- |
| Current development laptop | Write code, run tests, build the frontend, commit and push. | Development build commands below. |
| Spare runtime laptop | Pull the committed code and run the Docker deployment. It already has Docker Desktop, PostgreSQL 18, Ollama, Tailscale, and monitoring. Its clone is `C:\Users\Harshal S Pande\Documents\workspace\marketbrain`. | Deployment commands below. |

## Current development laptop: build and test

Run these from the repository root:

```powershell
Set-Location C:\Users\hpande\Documents\workspace\marketbrain

Set-Location .\marketbrain-service
mvn test

Set-Location ..\marketbrain-ui
npm ci
npm run build
```

The backend test suite does not require PostgreSQL. `npm run build` writes only the ignored `marketbrain-ui\dist` folder.

To inspect the changes before committing:

```powershell
Set-Location C:\Users\hpande\Documents\workspace\marketbrain
git status --short
git diff --check
```

## Current development laptop: run without Docker (optional)

Use two PowerShell windows. This is only needed when your development laptop also has a reachable local PostgreSQL database.

**Window 1 - backend**

```powershell
Set-Location C:\Users\hpande\Documents\workspace\marketbrain\marketbrain-service
$env:MARKETBRAIN_DB_URL = 'jdbc:postgresql://127.0.0.1:5432/marketbrain'
$env:MARKETBRAIN_DB_USERNAME = 'marketbrain_app'
$env:MARKETBRAIN_DB_PASSWORD = '<set your local database password here>'
$env:MARKETBRAIN_EXECUTION_MODE = 'PAPER'
mvn spring-boot:run
```

**Window 2 - dashboard**

```powershell
Set-Location C:\Users\hpande\Documents\workspace\marketbrain\marketbrain-ui
npm ci
npm run dev
```

Open `http://127.0.0.1:5173`. Stop either process with `Ctrl+C`.

## Spare runtime laptop: first deployment

Run these commands from the existing local Git clone after you have committed and pushed from the development laptop.

### 1. Verify host services

```powershell
docker version
Get-Service postgresql-x64-18 | Select-Object Name, Status, StartType
Test-NetConnection 127.0.0.1 -Port 5432
Invoke-RestMethod http://127.0.0.1:11434/api/version
```

Expected: Docker reports both client and server, PostgreSQL is `Running`, port `5432` succeeds, and Ollama returns a version. If Docker does not report a server, open Docker Desktop and wait for it to finish starting.

### 2. Pull the committed application code

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
```

`git status --short` should be empty before pulling. If it is not empty, do not overwrite those local changes; inspect them first.

### 3. Create local configuration once

```powershell
if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
}

notepad .env
```

In `.env`, set `MARKETBRAIN_DB_PASSWORD` to the existing password for the local `marketbrain_app` PostgreSQL user. Keep the remaining defaults for this phase, especially:

```properties
MARKETBRAIN_DB_URL=jdbc:postgresql://host.docker.internal:5432/marketbrain
MARKETBRAIN_DB_USERNAME=marketbrain_app
MARKETBRAIN_OLLAMA_BASE_URL=http://host.docker.internal:11434
MARKETBRAIN_PAPER_STARTING_CASH=100000
MARKETBRAIN_PAYTM_ENABLED=false
MARKETBRAIN_PAYTM_ACCESS_TOKEN=
MARKETBRAIN_UPSTOX_ENABLED=false
MARKETBRAIN_UPSTOX_ANALYTICS_TOKEN=
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

Do not add a Paytm token yet. Upstox is the current primary read-only data candidate and is enabled in the controlled procedure below.

### 4. Configure the private Telegram bot once

Keep the values only in the spare laptop's ignored `.env` file. Generate a random pairing code locally:

```powershell
$telegramPairingCode = [Convert]::ToHexString(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
)
$telegramPairingCode
```

Open `.env` and add or update these entries. Enter the token supplied by BotFather and the generated code locally; never put either value in Git or chat.

```properties
MARKETBRAIN_TELEGRAM_ENABLED=true
MARKETBRAIN_TELEGRAM_BOT_TOKEN=<enter the BotFather token locally>
MARKETBRAIN_TELEGRAM_PAIRING_CODE=<enter the generated code locally>
MARKETBRAIN_TELEGRAM_LONG_POLL_TIMEOUT_SECONDS=20
MARKETBRAIN_TELEGRAM_POLL_DELAY_MILLIS=1000
MARKETBRAIN_TELEGRAM_TEST_ALERTS_ENABLED=false
```

The bot uses outbound HTTPS only. It needs no public webhook, Cloudflare Tunnel, router port forwarding, or inbound firewall rule. Run only one MarketBrain backend with this bot token; two pollers would compete for the same updates.

### 5. Validate and start Docker services

```powershell
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

The first start applies the versioned MarketBrain database migration. It adds MarketBrain tables and types to the existing `marketbrain` database; it does not change PostgreSQL itself and does not create any broker order.

### 6. Check the running application

```powershell
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
Invoke-RestMethod http://127.0.0.1:8080/api/v1/system/status
Invoke-RestMethod http://127.0.0.1:8080/api/v1/data-sources
Invoke-RestMethod http://127.0.0.1:8080/api/v1/telegram/status

Start-Process http://127.0.0.1:8081
```

Expected:

- health returns `UP`;
- system status reports `PAPER`;
- Paytm Money reports `DISABLED`;
- Upstox reports `DISABLED` until the controlled read-only setup below is completed;
- Telegram reports `enabled=True`, `configured=True`, and initially `paired=False`;
- the dashboard shows a permanent PAPER MODE label.

### 7. Pair the private Telegram identity

In the private bot chat on the smartphone, send the following with the actual locally generated value:

```text
/pair <your local pairing code>
```

Do not send that code to a group or paste it into chat here. The bot should reply that MarketBrain was paired successfully. Verify from PowerShell:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/api/v1/telegram/status
```

Expected: `paired=True`. The bot now ignores messages and callbacks from every other Telegram identity. The earlier plain `/start` message does not pair an account by itself.

### 8. Perform the controlled Telegram test

Temporarily change this one `.env` value:

```properties
MARKETBRAIN_TELEGRAM_TEST_ALERTS_ENABLED=true
```

Recreate only the backend, then send one alert of each supported type manually:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

Invoke-RestMethod -Method Post 'http://127.0.0.1:8080/api/v1/telegram/test-alert?type=NOTE'
Invoke-RestMethod -Method Post 'http://127.0.0.1:8080/api/v1/telegram/test-alert?type=BUY'
Invoke-RestMethod -Method Post 'http://127.0.0.1:8080/api/v1/telegram/test-alert?type=SELL_HOLDING'
```

Expected:

- NOTE has no action buttons;
- BUY and SELL_HOLDING have `APPROVE`, `REJECT`, and `DETAILS`;
- each message is visibly labelled `TEST` and `PAPER MODE`;
- APPROVE is recorded but blocked because fresh-price and risk revalidation are not connected;
- no paper fill and no Paytm Money order can be created.

After testing, set `MARKETBRAIN_TELEGRAM_TEST_ALERTS_ENABLED=false` and apply it:

```powershell
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/api/v1/telegram/status
```

### 9. Configure and verify Upstox read-only market data

Prerequisite: generate an Upstox Analytics Token in the authenticated Upstox developer portal. The token is read-only and expires after its provider-defined lifetime. Never paste it into PowerShell history, Git, logs, source code, or chat.

Open the spare laptop's ignored `.env` file:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
notepad .env
```

Set these values locally. Paste the full token only into `.env` after the equals sign:

```properties
MARKETBRAIN_UPSTOX_ENABLED=true
MARKETBRAIN_UPSTOX_BASE_URL=https://api.upstox.com
MARKETBRAIN_UPSTOX_NSE_INSTRUMENT_URL=https://assets.upstox.com/market-quote/instruments/exchange/NSE.json.gz
MARKETBRAIN_UPSTOX_ANALYTICS_TOKEN=<paste the full Analytics Token locally>
```

Rebuild and start the backend. Flyway will add only the provider-instrument and quote-snapshot tables required for this phase:

```powershell
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build marketbrain-service
docker compose --env-file .env logs --tail=100 marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
Invoke-RestMethod http://127.0.0.1:8080/api/v1/data-sources
```

Expected: health is `UP`; Upstox reports `CONFIGURED_READ_ONLY`. The status call never displays the token.

Import the official NSE instrument master once. This downloads Upstox's documented NSE JSON/GZIP file and stores only NSE cash equities; it does not import futures or options:

```powershell
$instrumentImport = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/upstox/instruments/nse/import'
$instrumentImport | Format-List
```

Expected: `status=SUCCESS`, with non-zero `received` and `accepted` counts. A large `rejected` count is normal because the source file also contains non-equity instruments.

Run one controlled INFY quote check. `%7C` is the URL-encoded form of the `|` in the provider instrument key:

```powershell
$quote = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/upstox/quote?instrumentKey=NSE_EQ%7CINE009A01021'
$quote | Format-List
```

During market hours, expect `status=SUCCESS`, `qualityStatus=FRESH`, `actionable=True`, and `persisted=True`. Outside market hours, `STALE` and `actionable=False` are correct safety behavior—not a failure.

Finally, import a small historical daily sample:

```powershell
$candles = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/upstox/candles/import?instrumentKey=NSE_EQ%7CINE009A01021&unit=days&interval=1&fromDate=2026-08-25&toDate=2026-09-01'
$candles | Format-List
```

Expected: `status=SUCCESS`; accepted candles are stored idempotently. Repeating the same import updates the same source/time rows instead of duplicating them. This phase does not schedule collection, generate a signal, send a Telegram alert, execute a paper trade, or place a real broker order.

### 10. Run the controlled 15-year pilot backfill

This pilot covers only these ten configured symbols: `INFY`, `TCS`, `RELIANCE`, `HDFCBANK`, `ICICIBANK`, `SBIN`, `ITC`, `HINDUNILVR`, `LT`, and `BHARTIARTL`. Do not expand the list during this verification.

After pulling this increment, keep the worker disabled and deploy first. Flyway V5 creates the snapshot, job, chunk, and quality-control tables. Flyway V6 adds canonical daily-candle protection and safely collapses only identical same-date historical rows:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'

# Confirm this remains false in the ignored .env before the first deployment.
# MARKETBRAIN_BACKFILL_WORKER_ENABLED=false

docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build marketbrain-service
docker compose --env-file .env logs --tail=120 marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
```

Expected: health is `UP`, Flyway validates six migrations, and the schema reaches V6. No backfill starts merely because the service started.

Import and record the official current NIFTY 500 snapshot:

```powershell
$snapshot = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/current-snapshot'
$snapshot | Format-List
```

Expected: `status=SUCCESS`, approximately 500 source members, and approximately 500 matched members. Review `unmatchedSymbols`. Stop before creating a pilot if more than five symbols are unmatched, or if any of the ten pilot symbols is unmatched.

Create -- but do not start -- the 15-year pilot:

```powershell
$pilot = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/pilot?years=15'
$pilot | Format-List
$jobId = $pilot.jobId
```

If the PowerShell window is closed later, recover the persisted job ID with:

```powershell
$pilot = Invoke-RestMethod 'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $pilot.jobId
$pilot | Format-List
```

Expected before starting:

- `status=CREATED`;
- `instruments=10`;
- `totalChunks=150`;
- `completedChunks=0`;
- `workerEnabled=False`.

If those values are correct, open the ignored `.env`, change only the worker flag, and recreate the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=true
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
```

Start the reviewed job explicitly:

```powershell
$started = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/start?jobId=$jobId"
$started | Format-List
```

Monitor persisted checkpoints without printing credentials:

```powershell
do {
    $pilotStatus = Invoke-RestMethod `
        "http://127.0.0.1:8080/api/v1/market-data/backfills/status?jobId=$jobId"
    $pilotStatus | Select-Object status, progressPercent, completedChunks, retryChunks, failedChunks, acceptedRows, rejectedRows, connectivityFailureCount, connectivityRetryAt, lastConnectivityErrorCode
    if ($pilotStatus.status -in @('COMPLETED', 'PARTIAL_FAILED')) { break }
    Start-Sleep -Seconds 15
} while ($true)
```

Expected final state: `COMPLETED`, `completedChunks=150`, `failedChunks=0`, and non-zero `acceptedRows`. Some early yearly chunks may legitimately contain zero candles for companies listed less than 15 years ago.

If Wi-Fi, DNS, an Upstox rate limit, or a temporary Upstox server outage interrupts processing, the job changes to `WAITING_FOR_CONNECTIVITY`. The active chunk is returned to `RETRY` without consuming one of its three data-quality attempts. Automatic retries use persisted delays of 1 minute, 5 minutes, and then 15 minutes until connectivity returns. Completed chunks remain stored and are not repeated. If Telegram is enabled and paired, one system `NOTE` is attempted for the outage; it has no action buttons and creates no order.

The worker automatically continues when a retry succeeds. To retry immediately after restoring connectivity, use the manual resume endpoint:

```powershell
$resumed = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/resume?jobId=$jobId"
$resumed | Format-List
```

Use manual resume only when the status is `PAUSED` or `WAITING_FOR_CONNECTIVITY`. It remains blocked while the worker flag is false. Provider authentication errors and invalid response data are not mistaken for Wi-Fi failures; those remain subject to the maximum three controlled attempts and can result in `PARTIAL_FAILED` for investigation.

To stop new work safely at any point:

```powershell
Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/pause?jobId=$jobId"
```

Pausing does not terminate an in-flight HTTPS request; that one chunk may finish. After the pilot reaches a terminal state, return `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false` in `.env` and recreate the backend. Keep it disabled until the pilot results are reviewed.

This pilot stores raw daily candles only. It does not adjust corporate actions, claim historical NIFTY 500 membership, schedule daily updates, generate recommendations, send Telegram trade alerts, or create paper/live orders.

### 11. Audit the completed pilot data

Keep `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`. This audit is read-only: it does not update candles, create another backfill job, generate a recommendation, or place an order.

Recover the completed job ID and run the database-only audit first:

```powershell
$pilot = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $pilot.jobId

$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"

$quality | Select-Object qualityStatus, instrumentCount, totalCandles, blockingInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows, suspiciousGapCount, largeMoveCount | Format-List

$quality.instruments |
    Format-Table symbol, firstCandleDate, lastCandleDate, candleCount, longestCalendarGapDays, suspiciousGapCount, largeMoveCount, duplicateRows, invalidRows, status -AutoSize
```

Mandatory acceptance conditions:

- `instrumentCount=10` and `totalCandles` is non-zero;
- `blockingInstrumentCount=0`;
- `duplicateRows=0`;
- `invalidRows=0`.

`qualityStatus=REVIEW` is not automatically a failure. The audit deliberately treats calendar gaps over seven days and close-to-close moves over 20 percent as review candidates. These may indicate a suspension, a later listing, a split/bonus, or a genuine provider-data issue. Inspect the bounded finding lists:

```powershell
$quality.suspiciousGaps |
    Format-Table symbol, previousTradingDate, nextTradingDate, calendarGapDays -AutoSize

$quality.largeMoves |
    Format-Table symbol, tradingDate, previousClose, close, absoluteMovePercent -AutoSize
```

After the database checks pass, request the optional read-only Upstox spot comparison. This makes one historical-data request for each of the ten pilot stocks and compares the provider's latest candle within the completed job range with the stored candle:

```powershell
$verifiedQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId&providerSpotCheck=true"

$verifiedQuality | Select-Object qualityStatus, providerMismatchCount, providerCheckFailureCount | Format-List

$verifiedQuality.providerSpotChecks |
    Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize
```

Expected provider result: ten `MATCHED` rows, `providerMismatchCount=0`, and `providerCheckFailureCount=0`. A provider error does not change stored data; check connectivity and token validity before repeating the read-only audit. Stop before expanding the backfill if any instrument is `BLOCKED`, any stored/provider comparison is mismatched, or any finding cannot be explained.

### 12. Apply and verify the daily-candle correction before expansion

This correction must pass before creating the future job for the remaining NIFTY 500 instruments. Keep the historical worker disabled while deploying it:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build marketbrain-service
docker compose --env-file .env logs --tail=150 marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
```

Flyway V6 performs these guarded operations:

- preserves the original Upstox timestamp in `provider_opened_at`;
- collapses identical OHLCV rows representing the same Indian trading date;
- normalizes the stored daily-candle key to midnight in `Asia/Kolkata`;
- refuses the migration if same-date rows contain different OHLCV values;
- prevents a non-canonical daily timestamp from being stored again.

If the backend does not become healthy and the logs report conflicting daily candles, do not alter the Flyway history or manually delete data. Keep the worker disabled and investigate the reported data first.

Re-run the pilot quality report after a successful deployment:

```powershell
$pilot = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $pilot.jobId

$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"

$quality | Select-Object qualityStatus, instrumentCount, totalCandles, blockingInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows, suspiciousGapCount, largeMoveCount | Format-List
```

For the pilot result that contained nine identical duplicate rows, `totalCandles` should decrease from `37071` to `37062`; `duplicateRows` and `invalidRows` must both remain `0`. `INFY` and `SBIN` can remain under review for the separately observed large historical moves.

Use this read-only database check to verify that no duplicate daily trading-date groups remain and that all daily storage keys are canonical:

```powershell
$sql = @"
SELECT COUNT(*) AS duplicate_trading_date_groups
FROM (
    SELECT instrument_id, source_id,
           (opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date
    FROM market_candle
    WHERE interval_code = 'days:1'
    GROUP BY instrument_id, source_id,
             (opened_at AT TIME ZONE 'Asia/Kolkata')::date
    HAVING COUNT(*) > 1
) duplicates;

SELECT COUNT(*) AS noncanonical_daily_timestamps
FROM market_candle
WHERE interval_code = 'days:1'
  AND (opened_at AT TIME ZONE 'Asia/Kolkata')::time <> TIME '00:00:00';
"@

& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' `
    -h 127.0.0.1 `
    -p 5432 `
    -U marketbrain_app `
    -d marketbrain `
    -c $sql
```

Both counts must be `0`. The common ingestion path now protects every future stock. Identical same-date provider rows are collapsed before persistence; different OHLCV values for the same date stop that chunk for review. Do not start the remaining-instrument expansion until all checks in this section pass and the expansion endpoint has been implemented and reviewed.

## Spare runtime laptop: normal update and redeploy

Use this after each future commit and push from the development laptop:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=100 marketbrain-service
```

Run the health checks from the previous section after every deployment.

## Logs and stopping services

Follow backend logs:

```powershell
docker compose --env-file .env logs -f marketbrain-service
```

Follow dashboard logs:

```powershell
docker compose --env-file .env logs -f marketbrain-ui
```

Stop the MarketBrain containers without deleting native PostgreSQL data or Ollama models:

```powershell
docker compose --env-file .env down
```

Start previously built containers again:

```powershell
docker compose --env-file .env up -d
```

## Silent scheduled health monitoring and log retention

The existing `HealthCheck.ps1` remains the health-check implementation. The
tracked runner rotates its continuously appended `health.log` at the first run
of each new day and removes dated health logs older than 30 days. A VBScript
launcher runs the PowerShell runner without displaying a console window.

After pulling the repository on the spare laptop, run the tracked installer. It
copies the runner files and safely replaces the existing task definition:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
& '.\ops\windows\InstallHealthCheckTask.ps1'
```

It continues to run every 15 minutes under the signed-in Windows user, including
while the laptop is on battery. Overlapping executions are suppressed.

Test it immediately. No PowerShell window should appear:

```powershell
Start-ScheduledTask -TaskName 'MarketBrain-HealthCheck'
Get-ScheduledTaskInfo -TaskName 'MarketBrain-HealthCheck'
Get-Content 'C:\MarketBrainData\Monitoring\health.log' -Tail 3
```

`LastTaskResult` should be `0` after the run completes. The active file remains
`health.log`; completed days become `health-YYYY-MM-DD.log`. To change retention,
edit `RunHealthCheck.ps1` and change the default `RetentionDays` value. Do not
reduce it below seven days without a specific storage constraint.

## Basic troubleshooting

If the backend does not start, inspect its logs first:

```powershell
docker compose --env-file .env logs --tail=200 marketbrain-service
```

To check the native PostgreSQL login from the spare laptop:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -p 5432 -U marketbrain_app -d marketbrain -c "SELECT current_database(), current_user;"
```

If that command asks for a password, enter it locally. Do not paste it into chat. If it fails, correct only the local `.env` value and repeat the Docker start command.

If Telegram is enabled but the backend does not start, confirm locally that both `MARKETBRAIN_TELEGRAM_BOT_TOKEN` and `MARKETBRAIN_TELEGRAM_PAIRING_CODE` are non-empty. Do not print their values. Inspect only sanitized backend logs:

```powershell
docker compose --env-file .env logs --tail=200 marketbrain-service
```

If Telegram polling repeatedly fails, confirm the spare laptop has internet access and that no other application is polling with the same bot token. Provider exception messages are deliberately excluded from application logs so the token-bearing request URL cannot leak.

If Upstox returns `PROVIDER_ERROR`, confirm that `MARKETBRAIN_UPSTOX_ENABLED=true` and that the complete current Analytics Token is present in the local `.env`. Recreate the backend after changing `.env`. Do not print the token. An expired or replaced Analytics Token must be regenerated in Upstox and updated locally.

## Runbook maintenance rule

For every future MarketBrain change that affects building, configuration, Docker deployment, verification, or safe operation, this document will be updated in the same code change.
