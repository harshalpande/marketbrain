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
MARKETBRAIN_BACKFILL_MAXIMUM_EXPANSION_BATCH_SIZE=50
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
- collapses identical rows representing the same Indian trading date;
- safely merges a provider rounding difference of at most one paisa in the daily high or low by retaining the wider price range;
- normalizes the stored daily-candle key to midnight in `Asia/Kolkata`;
- refuses the migration if same-date rows differ in open, close, volume, completion state, or by more than one paisa in high or low;
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

Both counts must be `0`. The common ingestion path now protects every future stock. Identical same-date provider rows are collapsed before persistence. A difference of at most one paisa in high or low retains the wider range; material differences stop that chunk for review. Do not start the remaining-instrument expansion until all checks in this section pass and the expansion endpoint has been implemented and reviewed.

### 13. Deploy and verify calendar-aware coverage auditing

This step installs Flyway V7 and expands the existing read-only quality endpoint. V7 creates an auditable calendar containing the twelve officially verified NSE equity special sessions encountered during the pilot. It does not update or delete any candle.

Keep the historical worker disabled during this deployment:

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

Expected: health is `UP`, Flyway validates seven migrations, and the schema reaches V7. If Flyway fails, do not edit Flyway history or rerun the SQL manually; retain the logs and stop here.

Run the enhanced audit against the completed pilot:

```powershell
$pilot = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $pilot.jobId

$coverage = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"

$coverage | Select-Object qualityStatus, instrumentCount, totalCandles, blockingInstrumentCount, missingProviderDataInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows, officialSpecialSessionCount, missingOfficialSessionCount, peerConfirmedSessionCount, missingPeerConfirmedSessionCount, mutuallyAvailableTradingDateCount, modelTrainingEligible, backtestingEligible | Format-List

$coverage.officialSessionCoverage |
    Format-Table tradingDate, sessionType, eligibleInstrumentCount, presentInstrumentCount, missingInstrumentCount, status -AutoSize

$coverage.instruments |
    Format-Table symbol, candleCount, missingOfficialSessionCount, missingPeerConfirmedSessionCount, largeMoveCount, status -AutoSize

$coverage.missingOfficialSessions |
    Format-Table symbol, tradingDate, sessionType, evidenceType, status -AutoSize

$coverage.missingPeerConfirmedSessions |
    Format-Table symbol, tradingDate, evidenceType, status -AutoSize

$coverage.eligibilityReasons
```

For the current ten-stock pilot, expect:

- `officialSpecialSessionCount=12`;
- RELIANCE retains its genuine special-session candles;
- missing candles for other symbols are classified as `MISSING_PROVIDER_DATA`, not deleted, copied, or forward-filled;
- `duplicateRows=0`, `invalidRows=0`, and `blockingInstrumentCount=0` remain unchanged;
- `reviewInstrumentCount=2` continues to expose the separate INFY and SBIN large-move findings even though both instruments also have the higher-priority `MISSING_PROVIDER_DATA` status;
- `modelTrainingEligible=False` and `backtestingEligible=False` while any missing-data or review finding remains.

The peer-confirmed check separately detects an absent candle on an ordinary date when at least 80 percent of comparable, active pilot instruments contain that date. An instrument is considered active only between its own first and last stored candle, which avoids treating years before a company's listing as missing data. Official special sessions are excluded from this peer calculation because they already have stronger exchange provenance.

Finally, repeat the provider spot check. Eligibility can never become true unless this explicit check was requested and every other gate passed:

```powershell
$verifiedCoverage = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId&providerSpotCheck=true"

$verifiedCoverage | Select-Object qualityStatus, providerMismatchCount, providerCheckFailureCount, modelTrainingEligible, backtestingEligible | Format-List
$verifiedCoverage.providerSpotChecks |
    Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize
```

This audit is diagnostic only. It does not fetch replacement candles, change PostgreSQL market data, generate signals, or start the remaining NIFTY 500 backfill. Keep the worker disabled and share the four summary outputs above for review before proceeding to Step 14.

### 14. Create and run the first controlled NIFTY 500 expansion batch

Run this step only after Step 13 has been reviewed. The expansion is deliberately manual and sequential: one batch is created, inspected, started, completed, and audited before another batch can be created. The default and maximum batch size is 50 stocks.

Keep the worker disabled while deploying and creating the batch:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
MARKETBRAIN_BACKFILL_MAXIMUM_EXPANSION_BATCH_SIZE=50
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

Expected: health is `UP`, Flyway validates eight migrations, and the schema reaches V8. V8 classifies the existing job as `PILOT` and supports numbered expansion batches; it does not modify market candles.

Confirm the pilot now reports the missing-data and large-move dimensions independently:

```powershell
$pilot = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$pilotQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$($pilot.jobId)"
$pilotQuality | Select-Object qualityStatus, missingProviderDataInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows | Format-List
```

Expected for the reviewed pilot: `qualityStatus=MISSING_PROVIDER_DATA`, `missingProviderDataInstrumentCount=9`, `reviewInstrumentCount=2`, `duplicateRows=0`, and `invalidRows=0`.

Preview the first 50-stock expansion batch without writing a job:

```powershell
$batchPreview = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/next-batch-preview?years=15&batchSize=50'

$batchPreview | Select-Object batchNumber, selectedInstruments, remainingInstrumentsAfterBatch, totalChunks, manifestHash, listingEvidenceComplete, databaseWritesPerformed | Format-List
$batchPreview.instruments |
    Format-Table symbol, listedOn, nseReportedListedOn, listingBoundaryStatus, providerPrelistingCandleOn, effectiveFrom, totalChunks -AutoSize
```

If `listingEvidenceComplete=False`, prepare NSE evidence and reconcile any in-window security date against
earlier Upstox history. This writes only provenance and verified instrument boundaries; it does not create a
job or candle:

```powershell
$encodedInputHash = [uri]::EscapeDataString($batchPreview.manifestHash)
$listingEvidence = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/next-batch/listing-boundaries?years=15&batchSize=50&expectedManifestHash=$encodedInputHash" `
    -TimeoutSec 3600
$listingEvidence | Format-List

$batchPreview = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/next-batch-preview?years=15&batchSize=50'
```

Proceed only when `listingEvidenceComplete=True`. After the resulting manifest has been inspected,
create--but do not start--that exact batch:

```powershell
$encodedManifestHash = [uri]::EscapeDataString($batchPreview.manifestHash)
$batch = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/next-batch?years=15&batchSize=50&expectedManifestHash=$encodedManifestHash"

$batch | Select-Object batchNumber, selectedInstruments, remainingInstrumentsAfterBatch, maximumBatchSize, manifestHash, detail | Format-List
$batch.job | Format-List
$jobId = $batch.job.jobId
```

Expected for the first batch when approximately 500 snapshot members are matched:

- `batchNumber=1`;
- `selectedInstruments=50`;
- approximately `440` instruments remain after excluding the ten pilot stocks;
- `jobType=EXPANSION`, `status=CREATED`, and `workerEnabled=False`;
- `instruments=50`, `totalChunks=750`, and `completedChunks=0` for a 15-year request.

The exact remaining count can differ if the current snapshot has unmatched members. Inspect the complete deterministic symbol list before enabling the worker:

```powershell
$batchInstruments = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/instruments?jobId=$jobId"

$batchInstruments |
    Format-Table symbol, totalChunks, pendingChunks, runningChunks, retryChunks, completedChunks, failedChunks -AutoSize
```

Confirm there are exactly 50 unique symbols, none of the ten pilot symbols appear, every row has `totalChunks=15`, and every row initially has `pendingChunks=15`. If any condition fails, keep the worker disabled and stop.

After inspection, enable the worker locally and recreate only the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=true
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health

$started = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/start?jobId=$jobId"
$started | Format-List
```

Monitor the persisted job exactly as in the pilot:

```powershell
do {
    $batchStatus = Invoke-RestMethod `
        "http://127.0.0.1:8080/api/v1/market-data/backfills/status?jobId=$jobId"
    $batchStatus | Select-Object jobType, batchNumber, status, progressPercent, completedChunks, retryChunks, failedChunks, acceptedRows, rejectedRows, connectivityFailureCount, connectivityRetryAt, lastConnectivityErrorCode
    if ($batchStatus.status -in @('COMPLETED', 'PARTIAL_FAILED')) { break }
    Start-Sleep -Seconds 15
} while ($true)
```

All existing Wi-Fi recovery, persisted checkpoint, retry, pause, resume, and Telegram system-NOTE protections apply unchanged. A second batch cannot be created while this batch is `CREATED`, `RUNNING`, `WAITING_FOR_CONNECTIVITY`, or `PAUSED`. A `PARTIAL_FAILED` expansion also blocks the next batch until it is investigated.

After the job reaches `COMPLETED`, immediately disable the worker and recreate the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service

$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$quality | Select-Object qualityStatus, instrumentCount, totalCandles, blockingInstrumentCount, missingProviderDataInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows, missingOfficialSessionCount, missingPeerConfirmedSessionCount, mutuallyAvailableTradingDateCount | Format-List

$verifiedQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId&providerSpotCheck=true"
$verifiedQuality | Select-Object qualityStatus, providerMismatchCount, providerCheckFailureCount, modelTrainingEligible, backtestingEligible | Format-List
```

Mandatory conditions before considering the next batch:

- job `status=COMPLETED` and `failedChunks=0`;
- `blockingInstrumentCount=0`, `duplicateRows=0`, and `invalidRows=0`;
- `providerMismatchCount=0` and `providerCheckFailureCount=0`;
- every peer-confirmed missing session and large-move finding is reviewed;
- the worker is back to `False`.

Do not create batch 2 yet. Share the job summary, database-only quality summary, provider-verified summary, and any missing-session or large-move findings first. Subsequent batches use the same `next-batch` command only after the previous completed batch has been reviewed. Completed expansion instruments are automatically excluded, and a smaller final batch is created when fewer than 50 remain.

### 15. Apply the reviewed one-paisa normalization and recover batch 1

This step applies the correction reviewed after the first 50-stock expansion. It does five narrowly
scoped things:

- Flyway V9 records authoritative listing boundaries for `ANGELONE` and `360ONE`;
- quality audits and future backfill windows ignore data before those boundaries, while retaining the
  existing raw rows in PostgreSQL;
- near-identical same-date daily candles can be normalized only when every OHLC difference is at most
  one paisa and volume is identical;
- the known midnight/09:15 timestamp-transition pair can also be normalized when OHLC is exactly
  identical and the volume difference is both at most 100 shares and at most 0.01 percent;
- an explicit endpoint resets only failed `INVALID_DATA` chunks. Completed checkpoints are untouched.

Keep the worker disabled for the initial deployment:

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

Expected: health is `UP` and Flyway reports schema version V9. V9 does not delete or update any
`market_candle` row.

Confirm the two evidence-backed listing boundaries:

```powershell
$sql = @"
SELECT symbol, listed_on, listing_date_source_url
FROM instrument
WHERE exchange = 'NSE' AND symbol IN ('360ONE', 'ANGELONE')
ORDER BY symbol;
"@

& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' `
    -h 127.0.0.1 `
    -p 5432 `
    -U marketbrain_app `
    -d marketbrain `
    -c $sql
```

Expected: `360ONE=2019-09-19` and `ANGELONE=2020-10-05`, each with an NSE source URL.

Load and inspect the latest job before enabling any processing:

```powershell
$batchStatus = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$batchStatus | Format-List
$jobId = $batchStatus.jobId
```

Proceed only when this is expansion batch 1 with `status=PARTIAL_FAILED`, between one and four reviewed
`INVALID_DATA` chunks, and the worker is `False`. The original run found four affected chunks. If the
first three price-only cases were already recovered, only the remaining ALKEM chunk should be failed.
Then enable the worker locally and recreate only the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=true
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health

$retry = Invoke-RestMethod -Method Post `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/retry-invalid-data?jobId=$jobId"
$retry | Format-List
```

Expected: `status=RUNNING`. `retriedChunks=4` when running the complete correction once, or
`retriedChunks=1` when the first three chunks were recovered before the ALKEM correction. The endpoint
resets only chunks whose persisted state is `FAILED / INVALID_DATA`; it cannot retry connectivity,
runtime, or conflicting stored-data failures.

Monitor until all retried chunks finish:

```powershell
do {
    $batchStatus = Invoke-RestMethod `
        "http://127.0.0.1:8080/api/v1/market-data/backfills/status?jobId=$jobId"
    $batchStatus | Select-Object status, progressPercent, completedChunks, retryChunks, failedChunks, acceptedRows, rejectedRows
    if ($batchStatus.status -in @('COMPLETED', 'PARTIAL_FAILED')) { break }
    Start-Sleep -Seconds 5
} while ($true)
```

Expected: `status=COMPLETED`, `failedChunks=0`; ADANIENSOL, ADANIPORTS, and APOLLOTYRE each accept 246
canonical daily candles, while ALKEM accepts 172. Immediately disable the worker again and recreate the
backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
```

Verify the recovered chunks and their normalization audit records:

```powershell
$sql = @"
SELECT source_symbol, from_date, to_date, status, attempts,
       accepted_rows, rejected_rows, last_error_code
FROM historical_backfill_chunk
WHERE job_id = '$jobId'::uuid
  AND source_symbol IN ('ADANIENSOL','ADANIPORTS','ALKEM','APOLLOTYRE')
  AND from_date = DATE '2015-09-02'
  AND to_date = DATE '2016-09-01'
ORDER BY source_symbol;

SELECT chunk.source_symbol, issue.issue_code, issue.severity, issue.affected_rows, issue.details,
       issue.detected_at, issue.resolved_at
FROM market_data_quality_issue issue
JOIN historical_backfill_chunk chunk ON chunk.id = issue.chunk_id
WHERE issue.job_id = '$jobId'::uuid
  AND issue.issue_code = 'PROVIDER_DUPLICATE_NORMALIZED'
ORDER BY chunk.source_symbol;
"@

& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' `
    -h 127.0.0.1 `
    -p 5432 `
    -U marketbrain_app `
    -d marketbrain `
    -c $sql
```

Expected: all four chunks are `COMPLETED`. The three longer-history chunks each have
`accepted_rows=246`; ALKEM has `accepted_rows=172`. Each has one open
`PROVIDER_DUPLICATE_NORMALIZED / INFO` record with `affected_rows=1`. ALKEM's audit details must show
the retained 09:15 timestamp and volume 774426 plus the discarded midnight timestamp and volume 774495.

Finally repeat both quality audits:

```powershell
$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$quality | Select-Object qualityStatus, instrumentCount, totalCandles, blockingInstrumentCount, missingProviderDataInstrumentCount, reviewInstrumentCount, duplicateRows, invalidRows, missingOfficialSessionCount, missingPeerConfirmedSessionCount, mutuallyAvailableTradingDateCount | Format-List

$quality.instruments |
    Where-Object symbol -in @('360ONE','ANGELONE','APARINDS','ADANIENSOL','ADANIPORTS','ALKEM','APOLLOTYRE') |
    Format-Table symbol, firstCandleDate, lastCandleDate, candleCount, leadingCoverageGapDays, suspiciousGapCount, largeMoveCount, missingPeerConfirmedSessionCount, status -AutoSize

$quality.missingPeerConfirmedSessions |
    Where-Object symbol -eq 'APARINDS' |
    Format-List

$verifiedQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId&providerSpotCheck=true"
$verifiedQuality | Select-Object qualityStatus, providerMismatchCount, providerCheckFailureCount, modelTrainingEligible, backtestingEligible | Format-List
```

Expected interpretation:

- structural duplicates and invalid rows remain zero;
- all four failed yearly chunks are recovered without weakening the general conflict rule;
- `ANGELONE` begins at 2020-10-05 and `360ONE` begins at 2019-09-19 for analysis;
- APARINDS 2012-10-16 remains explicitly reported because Upstox currently supplies no candle for it;
- official special-session gaps remain separately reported and are never filled synthetically;
- `qualityStatus=MISSING_PROVIDER_DATA` and training/backtesting remain ineligible until those remaining
  findings are resolved or supported by an approved secondary source.

Do not create expansion batch 2. Share the retry result, recovered-chunk query, audit-record query, and
both quality summaries for review.

### 16. Deploy and verify governed quality resolutions

Run this step only after expansion batch 1 has reached `COMPLETED` with all 750 chunks complete. This
change does not alter or delete a market candle. It adds:

- read-only Upstox corporate-action evidence;
- an append-only review ledger with explicit revocation events;
- a database view containing mandatory feature-exclusion windows;
- resolved, documented, and unresolved counts in the quality response.

Deploy with the worker still disabled:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and then run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')

$latest = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $latest.jobId
$latest | Select-Object status, completedChunks, failedChunks, acceptedRows, workerEnabled | Format-List
```

Expected: `status=COMPLETED`, `completedChunks=750`, `failedChunks=0`, `acceptedRows=125167`, and
`workerEnabled=False`.

Inspect the new review projection before recording any decision:

```powershell
$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"

$quality | Select-Object qualityStatus, resolvedFindingCount, documentedFindingCount,
    unresolvedFindingCount, truncatedFindingCount, unresolvedMissingOfficialSessionCount,
    unresolvedMissingPeerConfirmedSessionCount, unresolvedSuspiciousGapCount,
    unresolvedLargeMoveCount, modelTrainingEligible, backtestingEligible | Format-List

$quality.qualityFindings |
    Format-Table findingType, symbol, findingDate, relatedDate, reviewStatus,
        resolutionType, allowsTraining, corporateActionTypes -AutoSize
```

Corporate-action retrieval uses the existing read-only Analytics Token held by the service. Sync only
symbols that have large-move findings, and do not paste the token into PowerShell:

```powershell
$largeMoveSymbols = @($quality.largeMoves.symbol | Sort-Object -Unique)

foreach ($symbol in $largeMoveSymbols) {
    Invoke-RestMethod -Method Post `
        "http://127.0.0.1:8080/api/v1/market-data/upstox/corporate-actions/sync?symbol=$([uri]::EscapeDataString($symbol))" |
        Select-Object status, symbol, isin, received, accepted, rejected
}

$quality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"

$quality.qualityFindings |
    Where-Object findingType -eq 'LARGE_MOVE' |
    Format-Table symbol, findingDate, reviewStatus, corporateActionTypes -AutoSize
```

Corporate-action evidence is advisory and never resolves a finding automatically. Before creating a
resolution, verify that the finding appears in `qualityFindings`, inspect its evidence, and choose one of
these controlled outcomes:

| Resolution | Allowed finding | Training effect |
| --- | --- | --- |
| `VERIFIED_EXCHANGE_MOVE` | Large move only | Preserves the genuine return. |
| `CORPORATE_ACTION_TRANSITION` | Large move with stored corporate-action evidence | Requires an exclusion window. |
| `PROVIDER_ADJUSTMENT` | Large move only | Requires an exclusion window. |
| `FEATURE_WINDOW_EXCLUDED` | Any non-structural finding | Requires an exclusion window. |
| `SECONDARY_SOURCE_BACKFILLED` | Missing session only | Accepted only if a non-Upstox candle already exists. |
| `PROVIDER_OMISSION_CONFIRMED` | Missing session only | Documents evidence but remains ineligible. |

This example safely documents the confirmed APARINDS omission without making the dataset eligible:

```powershell
$body = @{
    jobId = $jobId
    symbol = 'APARINDS'
    findingType = 'PEER_CONFIRMED_SESSION'
    findingDate = '2012-10-16'
    relatedDate = $null
    resolutionType = 'PROVIDER_OMISSION_CONFIRMED'
    evidenceSource = 'NSE official daily BhavCopy'
    evidenceUrl = 'https://nsearchives.nseindia.com/content/historical/EQUITIES/2012/OCT/cm16OCT2012bhav.csv.zip'
    notes = 'NSE EQ contains APARINDS, but the Upstox historical endpoint returns no candle.'
    reviewedBy = 'Harshal Pande'
    exclusionFrom = $null
    exclusionTo = $null
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions' `
    -ContentType 'application/json' `
    -Body $body | Format-List
```

Do not record the remaining resolutions in bulk. Review corporate-action evidence and NSE daily evidence
first. A corporate-action or provider-adjustment exclusion must include the finding date and remain inside
the backfill window. If a decision is wrong, append a revocation instead of deleting history:

```powershell
$revokeBody = @{
    jobId = $jobId
    symbol = 'APARINDS'
    findingType = 'PEER_CONFIRMED_SESSION'
    findingDate = '2012-10-16'
    relatedDate = $null
    evidenceSource = 'Operator correction'
    evidenceUrl = 'https://nsearchives.nseindia.com/content/historical/EQUITIES/2012/OCT/cm16OCT2012bhav.csv.zip'
    notes = 'Revoked for renewed review; no market candle was changed.'
    reviewedBy = 'Harshal Pande'
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions/revoke' `
    -ContentType 'application/json' `
    -Body $revokeBody
```

Inspect current resolutions and the exclusion view:

```powershell
Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId" |
    Format-Table findingType, symbol, findingDate, resolutionType, allowsTraining,
        exclusionFrom, exclusionTo, reviewedBy -AutoSize

$sql = @"
SELECT job_id, instrument_id, finding_type, finding_date,
       exclusion_from, exclusion_to, resolution_type, evidence_url
FROM market_data_feature_exclusion
WHERE job_id = '$jobId'::uuid
ORDER BY exclusion_from, instrument_id;
"@

& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' `
    -h 127.0.0.1 `
    -p 5432 `
    -U marketbrain_app `
    -d marketbrain `
    -c $sql
```

Finally request a fresh provider spot check:

```powershell
$verifiedQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId&providerSpotCheck=true"

$verifiedQuality | Select-Object qualityStatus, providerMismatchCount,
    providerCheckFailureCount, resolvedFindingCount, documentedFindingCount,
    unresolvedFindingCount, truncatedFindingCount, modelTrainingEligible, backtestingEligible | Format-List

$verifiedQuality.eligibilityReasons
```

`modelTrainingEligible` and `backtestingEligible` must remain `False` while any finding is merely
documented or unresolved. Structural duplicate/invalid-candle findings can never be overridden. Do not
create expansion batch 2 until this output has been reviewed.

### 17. Generate the read-only official NSE large-move evidence report

Run this only after step 16 has been reviewed. This endpoint downloads an official NSE Bhavcopy once for
each distinct large-move date and compares its previous close and close with the stored Upstox values. It
supports the legacy NSE cash-market Bhavcopy and the UDiFF format used from 8 July 2024. NSE documents the
format transition on its [All Reports](https://www.nseindia.com/all-reports) page.

This operation is deliberately read-only:

- it does not insert or update a market candle;
- it does not create a quality resolution or feature exclusion;
- it matches by ISIN before symbol, so renamed securities can retain their historical NSE symbol;
- unavailable archives and unmatched instruments remain open rather than being guessed.

Deploy with the backfill worker still disabled:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and then run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')

$latest = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $latest.jobId

$beforeQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$beforeResolutionResponse = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
$beforeResolutionCount = @(
    $beforeResolutionResponse | Where-Object { $null -ne $_ }
).Count

$latest |
    Select-Object status, completedChunks, failedChunks, acceptedRows, workerEnabled |
    Format-List
```

Expected: the completed job remains at 750 completed chunks, zero failed chunks, 125167 accepted rows,
and `workerEnabled=False`.

Verify one legacy-format finding and one UDiFF-format finding before requesting the full report:

```powershell
$legacyEvidence = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/large-move-evidence?jobId=$jobId&symbol=ABB"

$legacyEvidence |
    Select-Object findingCount, sourceRequestCount, officialMatchCount, officialMismatchCount,
        sourceUnavailableFindingCount, symbolNotFoundCount, resolutionsWritten |
    Format-List

$legacyEvidence.findings |
    Format-Table symbol, findingDate, evidenceStatus, officialSymbol, matchBasis,
        storedPreviousClose, officialPreviousClose, storedClose, officialClose, reviewPath -AutoSize

$udiffEvidence = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/large-move-evidence?jobId=$jobId&symbol=ADANIGREEN"

$udiffEvidence |
    Select-Object findingCount, sourceRequestCount, officialMatchCount, officialMismatchCount,
        sourceUnavailableFindingCount, symbolNotFoundCount, resolutionsWritten |
    Format-List

$udiffEvidence.findings |
    Format-Table symbol, findingDate, evidenceStatus, officialSymbol, matchBasis,
        storedPreviousClose, officialPreviousClose, storedClose, officialClose, reviewPath -AutoSize
```

For both samples, `resolutionsWritten` must be `False`. If either request returns
`CONNECTION_FAILED`, `RATE_LIMITED`, `SOURCE_NOT_FOUND`, `SOURCE_REJECTED`, `SOURCE_UNAVAILABLE`, or
`INVALID_SOURCE_ARCHIVE`, stop and share the result; do not record a resolution.

If both formats were read successfully, request all 28 findings:

```powershell
$evidence = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/large-move-evidence?jobId=$jobId"

$evidence |
    Select-Object findingCount, sourceRequestCount, officialMatchCount, officialMismatchCount,
        sourceUnavailableFindingCount, symbolNotFoundCount, corporateActionDateMatchCount,
        resolutionsWritten |
    Format-List

$evidence.findings |
    Format-Table symbol, findingDate, evidenceStatus, officialSymbol, matchBasis,
        storedPreviousClose, officialPreviousClose, storedClose, officialClose,
        corporateActionTypes, reviewPath -AutoSize

$afterQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$afterResolutionResponse = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
$afterResolutionCount = @(
    $afterResolutionResponse | Where-Object { $null -ne $_ }
).Count

[pscustomobject]@{
    CandlesBefore = $beforeQuality.totalCandles
    CandlesAfter = $afterQuality.totalCandles
    ResolutionsBefore = $beforeResolutionCount
    ResolutionsAfter = $afterResolutionCount
    ResolutionsWrittenByReport = $evidence.resolutionsWritten
} | Format-List
```

`CandlesBefore` must equal `CandlesAfter`, `ResolutionsBefore` must equal `ResolutionsAfter`, and
`ResolutionsWrittenByReport` must be `False`. The `reviewPath` field is only a proposed human-review route;
it is not an approved resolution. Do not create resolution records or expansion batch 2. Share both sample
reports, the full summary/table, and the final before/after safety check for review.

### 18. Re-run large-move evidence with adjusted-return and historical-identity classification

Run this only after step 17 reports all 28 source requests without an unavailable archive. This refinement
keeps the endpoint read-only while distinguishing an adjusted price series from a genuine return mismatch.
It compares both close-to-close returns and the official/stored scale ratio. A non-exact price pair is treated
as an adjusted-return match only when the return difference is at most 0.50 percentage points and the two
scale ratios differ by at most 0.50 percent.

The migration also records evidence-backed, effective-dated AMIORG identities for the current ACUTAAS
lineage. The audited 29 January 2025 row is matched using the historical ISIN; no current instrument or candle
identity is rewritten.

Keep the backfill worker disabled and deploy:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')

$latest = Invoke-RestMethod `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/latest'
$jobId = $latest.jobId

$beforeQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$beforeResolutionResponse = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
$beforeResolutionCount = @(
    $beforeResolutionResponse | Where-Object { $null -ne $_ }
).Count

$evidence = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/large-move-evidence?jobId=$jobId"

$evidence |
    Select-Object findingCount, sourceRequestCount, officialMatchCount,
        officialAdjustedReturnMatchCount, officialMismatchCount,
        sourceUnavailableFindingCount, symbolNotFoundCount,
        corporateActionDateMatchCount, resolutionsWritten |
    Format-List

$evidence.findings |
    Format-Table symbol, findingDate, evidenceStatus, officialSymbol, matchBasis,
        storedReturnPercent, officialReturnPercent, returnDifferencePercentagePoints,
        previousCloseScaleRatio, closeScaleRatio, scaleRatioDifferencePercent, reviewPath -AutoSize
```

Expected full-report reconciliation:

- `findingCount=28` and `sourceRequestCount=28`;
- `officialMatchCount=16` for exact official prices;
- `officialAdjustedReturnMatchCount=6` for ABB, three ADANIPOWER dates, ANANTRAJ, and ACUTAAS;
- `officialMismatchCount=6` for the two ACE and four ASHOKLEY findings;
- `sourceUnavailableFindingCount=0`, `symbolNotFoundCount=0`, and `resolutionsWritten=False`;
- ACUTAAS on 29 January 2025 has `officialSymbol=AMIORG` and `matchBasis=HISTORICAL_ISIN`.

Complete the read-only safety check:

```powershell
$afterQuality = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality?jobId=$jobId"
$afterResolutionResponse = Invoke-RestMethod `
    "http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions?jobId=$jobId"
$afterResolutionCount = @(
    $afterResolutionResponse | Where-Object { $null -ne $_ }
).Count

[pscustomobject]@{
    CandlesBefore = $beforeQuality.totalCandles
    CandlesAfter = $afterQuality.totalCandles
    ResolutionsBefore = $beforeResolutionCount
    ResolutionsAfter = $afterResolutionCount
    ResolutionsWrittenByReport = $evidence.resolutionsWritten
} | Format-List
```

The candle and resolution counts must remain unchanged, and `ResolutionsWrittenByReport` must be `False`.
Do not create governed resolutions or expansion batch 2 yet. Share the summary, full classification table,
and safety check for review.

### 19. Preview and apply the 22 verified large-move resolutions

Run this only after step 18 returns the exact `16 + 6 + 6` classification and passes its read-only safety
check. The script has two explicit modes:

- preview mode validates the completed job, disabled worker, full 22-finding identity set, evidence statuses,
  and a fixed SHA-256 manifest; it writes nothing;
- apply mode requires the exact hash printed by the reviewed preview, skips an already-correct resolution,
  rejects a conflicting resolution, and appends only `VERIFIED_EXCHANGE_MOVE` audit events.

The two ACE and four ASHOKLEY findings are not in the approved manifest and remain open. The backend also
rejects a second current resolution for the same finding, so an interrupted apply can be safely reviewed and
resumed without intentionally duplicating a current resolution.

Deploy with the worker disabled:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')
```

Run preview mode first:

```powershell
& '.\ops\windows\ResolveVerifiedLargeMoves.ps1'
```

Expected preview invariants:

- `Mode=PREVIEW_ONLY`;
- `ManifestHash=726ab4d0cb4c697e9dd35d801ebfa87ad4bca1adb854517c994d662999eed4c1`;
- `CandidateCount=22`;
- `PendingCandidateCount=22`, unless an identical verified resolution already exists;
- `CandlesBefore=124858` and `WorkerEnabled=False`;
- the final message states that no resolution or candle was written.

The preview also prints every current resolution. Stop if the existing-resolution list or any manifest value
is unexpected, and share the complete preview. Do not proceed merely because the command returned without an
HTTP error.

After the preview has been explicitly reviewed, apply that exact manifest. `ReviewedBy` is audit metadata;
use the name of the person who actually reviewed the preview:

```powershell
& '.\ops\windows\ResolveVerifiedLargeMoves.ps1' `
    -Apply `
    -ReviewedBy 'Harshal Pande' `
    -ExpectedManifestHash '726ab4d0cb4c697e9dd35d801ebfa87ad4bca1adb854517c994d662999eed4c1'
```

Expected final invariants:

- `Status=COMPLETED` and `WrittenResolutionCount=22`, reduced only by already-correct candidates;
- the current resolution count increases by the written count;
- `CandlesBefore=124858` and `CandlesAfter=124858`;
- `UnresolvedLargeMovesBefore=28` and `UnresolvedLargeMovesAfter=6` on the first apply;
- training and backtesting remain ineligible because missing-session and leading-coverage findings are still
  unresolved.

If the apply is interrupted, run preview mode again before resuming. The remaining pending count must explain
the difference. Do not manually delete resolution events, edit candles, or start expansion batch 2. Share the
preview and final apply summaries for review.

### 20. Analyze every remaining 50-stock quality finding in one read-only run

This step replaces manual finding-by-finding investigation with one governed analysis command. It analyzes
all remaining missing-session, coverage-gap, and large-move findings, but does not modify a candle, feature
exclusion, or quality resolution. The complete proposed plan is bound to a SHA-256 `PlanHash` and saved as a
local JSON review artifact.

Step 20 requires the reviewed Step 19 checkpoint: 50 instruments, 750 completed chunks, 124858 unique daily
candles, 22 current verified resolutions, 331 unresolved findings, six unresolved large moves, no duplicate
rows, no invalid rows, and a disabled backfill worker.

Deploy with the worker disabled:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')

& '.\ops\windows\AnalyzeRemainingDataQuality.ps1'
```

The command can take longer than the previous checks because each distinct required NSE archive is fetched
once. It prints a compact classification rather than hundreds of repetitive rows and saves the complete plan
under `C:\MarketBrainData\Review`.

Expected safety invariants:

- `Status=COMPLETED`; if it says `REVIEW_REQUIRED`, stop and share the open/source-failure rows;
- `UnresolvedFindingCount=331`, split across 298 official-session findings, two peer-session findings,
  25 coverage gaps, and six large moves;
- `KeepOpenCount=0` and `SourceFailureCount=0` before Step 21 can be designed for this exact plan;
- `CandlesBefore=124858` and `CandlesAfter=124858`;
- `ResolutionsBefore=22` and `ResolutionsAfter=22`;
- `WorkerEnabled=False`, `candlesWritten=False`, and `resolutionsWritten=False`;
- `PlanHash` is a 64-character lowercase SHA-256 value.

Share the complete summary, recommendation table, any keep-open table, and `PlanHash`. Do not share database
credentials. Keep the JSON artifact for audit, but do not edit it or use it as an executable input.

### 21. Apply the reviewed remaining-data plan through one resumable command

The reviewed Step 20 plan is approved for job `e1d9ea5d-fcb2-4a81-b839-c154bb602243` with SHA-256 hash
`3ea264d124b3618dc793a66677e1b040736d65ad49b230309b60647b1c64b7f8`. It contains exactly 331 actions:

- 277 validated NSE BhavCopy candles followed by `SECONDARY_SOURCE_BACKFILLED` resolutions;
- 48 explicit `FEATURE_WINDOW_EXCLUDED` resolutions, comprising 25 leading-coverage windows and 23 sessions
  where the official archive contained no supported instrument record;
- six one-day `PROVIDER_ADJUSTMENT` exclusions for the reviewed ACE and ASHOKLEY mismatches.

The operation is one command for the operator, but it is not one large transaction. On the first run the
backend independently recreates Step 20 and refuses to proceed unless its live hash still equals the reviewed
hash. It then persists the entire plan before changing market data. Every finding is completed in its own
transaction: an NSE candle and its resolution either both commit or both roll back. Completed items are
durable checkpoints, so rerunning the same command skips them and retries only pending or failed items.

The 277 exchange candles use the separate `NSE_BHAVCOPY` source. Existing Upstox candles are never updated or
deleted. If Wi-Fi fails before the reviewed plan is persisted, nothing is applied. Once the plan is persisted,
the remaining work uses the stored official evidence and local PostgreSQL; a service or power interruption is
recovered by running the same command again.

Deploy with the worker disabled:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git pull --ff-only
notepad .env
```

Confirm `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, save, and run:

```powershell
docker compose --env-file .env up -d --build marketbrain-service

do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
    } catch {
        $health = $null
    }
} until ($health.status -eq 'UP')

& '.\ops\windows\ApplyRemainingDataPlan.ps1' -ReviewedBy 'Harshal Pande'
```

The first run may take longer while the backend revalidates 20 immutable NSE archives. Keep the terminal open.
Expected final invariants are:

- `Status=COMPLETED`, `TotalItems=331`, `CompletedItems=331`, `PendingItems=0`, and `FailedItems=0`;
- `SecondaryBackfillItems=277`, `FeatureExclusionItems=48`, and `ProviderAdjustmentItems=6`;
- `SecondaryCandlesReady=277`;
- `UpstoxDailyCandleCount=125167`, `SecondaryDailyCandleCount=277`, and
  `AllSourceDailyCandleCount=125444`; the quality audit separately reports 124858 Upstox candles inside each
  instrument's effective listing and job boundaries;
- `PlanResolutionsWritten=331`, `CurrentResolutionCount=353`, and `UnresolvedFindingCount=0`;
- `WorkerEnabled=False` and the returned hash exactly matches the reviewed Step 20 hash.

If the result is `PARTIAL_FAILED`, do not delete a candle, resolution, plan, or checkpoint. Correct only the
reported environmental problem and rerun the exact same command with the same `ReviewedBy` name. It will not
download the plan again or duplicate completed work. If the PowerShell request itself is interrupted, run the
same command again; the persisted checkpoints remain authoritative.

Step 21 resolves the reviewed historical findings, but model-training and backtesting eligibility still
require one final live provider spot check. Do not start expansion batch 2 until the Step 21 summary has been
reviewed and that final gate has passed.

### 22. Run the final provider-backed quality gate for the first 50 stocks

This is a read-only gate. It first validates the persisted Step 21 checkpoint and then requests a fresh
Upstox comparison for every instrument. It saves the complete response under `C:\MarketBrainData\Review` and
proves that neither the remediation count nor the resolution count changed during verification.

Keep `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false` and run:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
& '.\ops\windows\VerifyFinalBackfillQuality.ps1'
```

The command makes 50 read-only provider requests, paced below the provider's standard per-second limit, and
can take some time. Expected final invariants are:

- `Status=ELIGIBLE`, `QualityStatus=PASS`, and `InstrumentCount=50`;
- `QualityScopedUpstoxCandles=124858`, zero blocking instruments, zero unresolved findings, zero duplicates,
  zero invalid rows, and zero truncated findings;
- `ResolvedFindingCount=353` and `DocumentedFindingCount=0`;
- `ProviderSpotCheckRequested=True`, `ProviderSpotCheckCount=50`, `ProviderMismatchCount=0`, and
  `ProviderCheckFailureCount=0`;
- every provider check has `status=MATCHED`;
- `ModelTrainingEligible=True`, `BacktestingEligible=True`, and `WorkerEnabled=False`.

The raw missing-session and large-move counts remain visible as audit history; their corresponding unresolved
counts must be zero. A provider outage, token problem, or rate limit can make this gate fail without changing
any data. Correct only that environmental problem and rerun the same command. Do not weaken the gate or
manually alter its JSON report.

Share the complete summary and any non-matching provider rows before starting expansion batch 2.

### 23. Prepare the reviewed expansion batch 2 manifest

Run this only after Step 22 reports `Status=ELIGIBLE`. This step revalidates the completed first expansion
batch against Upstox and then calculates the next deterministic 50-stock selection. It is deliberately
read-only: no backfill job, chunk, candle, finding, or resolution is inserted.

Keep `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, deploy the reviewed code, and run:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build marketbrain-service
Invoke-RestMethod http://127.0.0.1:8080/actuator/health

& '.\ops\windows\PreviewNextExpansionBatch.ps1'
```

The provider-backed prerequisite check makes one request per instrument and can take some time. Expected
invariants for this checkpoint are:

- the initial result can be `Status=LISTING_EVIDENCE_REQUIRED`; after Step 24 it must be
  `Status=REVIEW_REQUIRED`;
- `CompletedBatchNumber=1` and `CompletedBatchQualityStatus=PASS`;
- `CompletedBatchProviderChecks=50` and no mismatch or provider failure;
- `NextBatchNumber=2`, `SelectedInstruments=50`, and `Years=15`;
- every proposed symbol is unique and every instrument has at least one yearly chunk;
- `ManifestHash` is a 64-character SHA-256 value;
- `ListingEvidenceComplete=True` before creation can be approved;
- `DatabaseWritesPerformed=False` and `WorkerEnabled=False`;
- a complete JSON report is saved under `C:\MarketBrainData\Review`.

All expansion batches reuse the historical date boundaries frozen by expansion batch 1. For the current
snapshot, Step 23 should therefore report `RequestedFrom=2011-09-02` and `RequestedTo=2026-09-01`, even when
the preview is run later. If the snapshot, frozen boundary, completed-job set, or symbol selection changes,
the hash changes and creation using an older reviewed hash is rejected.

Share the complete summary and proposed instrument table for review. Do not call the creation endpoint and do
not enable the worker until the listing-evidence result has been reviewed.

### 24. Reconcile official listing evidence and regenerate the batch 2 manifest

Run this only after the Step 23 preview has been reviewed and `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false` is
confirmed. The command downloads the official NSE equity-security CSV, verifies the file structure and SHA-256
identity, and matches every proposed symbol by both symbol and ISIN.

For an NSE-reported date inside the requested history window, it searches Upstox backwards from the day before
that date. If an older provider candle exists, the NSE date is preserved as security metadata but is not used
to truncate history. If no older candle exists across the requested window, the boundary is applied with its
NSE source URL. Any provider, identity, format, or connectivity failure causes the preparation to stop without
writing partial evidence.

Keep the worker disabled, deploy the reviewed code, and run:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build marketbrain-service

$health = $null
for ($attempt = 1; $attempt -le 24; $attempt++) {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
        if ($health.status -eq 'UP') { break }
    } catch {
        # The backend may still be starting.
    }
    Start-Sleep -Seconds 5
}
if ($null -eq $health -or $health.status -ne 'UP') {
    throw 'MarketBrain did not become healthy within two minutes.'
}

& '.\ops\windows\PrepareNextExpansionListingBoundaries.ps1'
```

The script writes a full evidence report under `C:\MarketBrainData\Review` and then automatically regenerates
the read-only batch preview. Mandatory conditions are:

- enrichment `Status=COMPLETED`, `CandidateCount=50`, and `MatchedEvidenceCount=50`;
- the four classification counts sum to 50;
- `ProviderCheckFailureCount=0`, `EvidenceRowsWritten=50`, and `ListingEvidenceComplete=True`;
- the regenerated preview reports `Status=REVIEW_REQUIRED` and `ListingEvidenceComplete=True`;
- the output manifest hash is 64 hexadecimal characters;
- no backfill job or candle was created and the worker remains disabled.

`TotalChunks` may now be below 750 because verified post-2011 listing boundaries avoid empty pre-listing yearly
requests. Blank `listedOn` is acceptable only for `BEFORE_REQUEST_WINDOW` or `EARLIER_PROVIDER_HISTORY`; the
corresponding raw NSE date and reconciliation status remain visible.

Share the complete enrichment summary, decision table, and regenerated preview. Do not create batch 2 or
enable the worker until Step 25 is explicitly approved.

### 25. Create the exact reviewed expansion batch 2 without starting it

Run this only after the complete Step 24 output has been reviewed and explicitly approved. The script requires
the exact reviewed manifest hash and the saved Step 24 preview file. It recalculates the live selection before
calling the creation endpoint, and the backend independently rejects a stale or changed manifest.

Creation writes one `CREATED` job and its `PENDING` chunk checkpoints in a single database transaction. It does
not download or write any candle, and it never enables the worker or calls the start endpoint.

Keep `MARKETBRAIN_BACKFILL_WORKER_ENABLED=false`, pull the reviewed script, and run it with the manifest hash
from Step 24:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'

& '.\ops\windows\CreateReviewedExpansionBatch.ps1' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8' `
    -ReviewedBy 'Harshal Pande'
```

For the reviewed Batch 2 manifest, mandatory conditions are:

- `Status=CREATED_NOT_STARTED` (or `RECOVERED_CREATED_NOT_STARTED` after an interrupted first invocation),
  `BatchNumber=2`, and the returned manifest hash exactly matches Step 24;
- `SelectedInstruments=50`, `RemainingAfterBatch=390`, and `TotalChunks=623`;
- `PendingChunks=623`, while running, completed, and failed chunks are all zero;
- `ListingEvidenceComplete=True`, `ManifestMismatchCount=0`, and `NonPendingInstrumentCount=0`;
- `WorkerEnabled=False`;
- all 50 instrument rows have only pending chunks, with their per-symbol totals matching the reviewed preview;
- a complete creation report is saved under `C:\MarketBrainData\Review`.

If an earlier invocation successfully created Batch 2 but failed or was interrupted during local verification,
rerunning the same command recognizes the matching inactive `CREATED` job. It sends no creation request and
performs the complete read-only checkpoint verification against the saved Step 24 manifest. It never deletes or
recreates the job.

Share the complete Step 25 summary and instrument table. Do not enable the worker or start Batch 2 until the
creation checkpoint is reviewed and the next step is explicitly approved.

### 26. Start and monitor the exact reviewed expansion batch 2

Run this only after Step 25 reports a clean `CREATED_NOT_STARTED` or `RECOVERED_CREATED_NOT_STARTED` checkpoint
and its complete output has been approved. First open the ignored local `.env` file and change only:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=true
```

Recreate only the backend and wait for health:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
notepad .env
docker compose --env-file .env up -d marketbrain-service

$health = $null
for ($attempt = 1; $attempt -le 24; $attempt++) {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
        if ($health.status -eq 'UP') { break }
    } catch {
        # The backend may still be starting.
    }
    Start-Sleep -Seconds 5
}
if ($null -eq $health -or $health.status -ne 'UP') {
    throw 'MarketBrain did not become healthy within two minutes.'
}
```

Start and monitor only the exact Step 25 job:

```powershell
& '.\ops\windows\RunReviewedExpansionBatch.ps1' `
    -JobId '7e8a79ec-045c-4474-b3e8-78e716e11143' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
```

The script validates the saved Step 25 creation report, live job identity, immutable dates, 50-symbol manifest,
provider keys, and all 623 chunk checkpoints before starting. It is restart-safe: rerunning it while the job is
`RUNNING` or `WAITING_FOR_CONNECTIVITY` sends no new start request and resumes read-only monitoring. Closing the
terminal stops only the monitor; the Docker backend continues from PostgreSQL checkpoints.

During an internet or temporary Upstox outage, `WAITING_FOR_CONNECTIVITY` is expected. The affected chunk is
kept as `RETRY`, completed chunks are not repeated, and the backend automatically resumes after the persisted
delay. Do not manually start, resume, delete, or reset the job while automatic recovery is active.

A clean terminal checkpoint requires:

- `Status=COMPLETED`, `Instruments=50`, and `TotalChunks=623`;
- pending, running, retry, and failed chunks all equal zero;
- `CompletedChunks=623`, `RejectedRows=0`, and `FailedInstrumentCount=0`;
- a full run report under `C:\MarketBrainData\Review`.

Immediately after a terminal result, change the local `.env` flag back to false and recreate only the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod 'http://127.0.0.1:8080/api/v1/market-data/backfills/latest' |
    Select-Object jobId, batchNumber, status, completedChunks, failedChunks, acceptedRows, rejectedRows, workerEnabled |
    Format-List
```

Share the complete Step 26 terminal summary, any failed-instrument table, and the disabled-worker status. Do not
begin Batch 2 quality correction or prepare Batch 3 until this checkpoint is reviewed.

### 27. Recover the reviewed BEML split-adjustment rounding duplicate

Use this only for Batch 2 job `7e8a79ec-045c-4474-b3e8-78e716e11143` after Step 26 reports exactly one failed
chunk: BEML, `2015-09-02` through `2016-09-01`, three attempts, and `INVALID_DATA`.

The provider returned 247 rows with two representations of 31 December 2015. Both have open `640.60`, high
`645.50`, low `633.00`, and volume `392016`; their closes are `640.50` at midnight and `640.60` at 09:15. The
official NSE Bhavcopy has one pre-split row (`1281.15`, `1290.95`, `1266.10`, `1281.10`, volume `196008`), and
BEML's official 2025 filing records the subsequent 1:2 face-value split.

The correction is an exact authorization for this instrument key, date, timestamp pair, and OHLCV pair. It
does not increase the general one-paisa rule. It retains the exchange-aligned 09:15 provider row and records
both original OHLCV rows, the Bhavcopy URL, the split filing URL, and the adjustment ratio in the existing
`PROVIDER_DUPLICATE_NORMALIZED` audit issue.

Keep the worker disabled while deploying the correction:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=false
```

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
docker compose --env-file .env up -d --build marketbrain-service
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'
```

Then change only the worker flag to true and recreate the backend:

```properties
MARKETBRAIN_BACKFILL_WORKER_ENABLED=true
```

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'

& '.\ops\windows\RecoverReviewedBemlChunk.ps1' `
    -JobId '7e8a79ec-045c-4474-b3e8-78e716e11143' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
```

The endpoint can reset only failed `INVALID_DATA` chunks, and the script additionally requires the reviewed
reports and exactly one failed BEML instrument. A clean result has `Status=COMPLETED`, `RetriedChunks=1`,
`CompletedChunks=623`, `FailedChunks=0`, `AcceptedRows=149636`, `RejectedRows=0`,
`BemlCompletedChunks=15`, and `BemlFailedChunks=0`.

Immediately set the worker flag back to false and recreate only the backend. Then verify the exact checkpoint
and audit evidence:

```powershell
notepad .env
docker compose --env-file .env up -d marketbrain-service

$jobId = '7e8a79ec-045c-4474-b3e8-78e716e11143'
$sql = @"
SELECT source_symbol, from_date, to_date, status, attempts,
       accepted_rows, rejected_rows, last_error_code
FROM historical_backfill_chunk
WHERE job_id = '$jobId'::uuid
  AND source_symbol = 'BEML'
  AND from_date = DATE '2015-09-02'
  AND to_date = DATE '2016-09-01';

SELECT issue.issue_code, issue.severity, issue.affected_rows, issue.details,
       issue.detected_at, issue.resolved_at
FROM market_data_quality_issue issue
JOIN historical_backfill_chunk chunk ON chunk.id = issue.chunk_id
WHERE issue.job_id = '$jobId'::uuid
  AND chunk.source_symbol = 'BEML'
  AND issue.issue_code = 'PROVIDER_DUPLICATE_NORMALIZED';
"@

& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' `
    -h 127.0.0.1 `
    -p 5432 `
    -U marketbrain_app `
    -d marketbrain `
    -c $sql

Invoke-RestMethod 'http://127.0.0.1:8080/api/v1/market-data/backfills/latest' |
    Select-Object status, completedChunks, failedChunks, acceptedRows, rejectedRows, workerEnabled |
    Format-List
```

Expected: the BEML chunk is `COMPLETED` with 246 accepted rows and one normalized duplicate; the audit detail
contains `REVIEWED_SPLIT_ADJUSTMENT_CLOSE_ROUNDING`, both provider OHLCV values, both official evidence URLs,
and `reviewedAdjustment=1:2`. The final API status must show `COMPLETED`, 623 completed chunks, zero failures,
149636 accepted rows, zero rejected rows, and `workerEnabled=False`.

Share the complete recovery summary, both SQL results, and the disabled-worker status. Do not run Batch 2
quality remediation or prepare Batch 3 until this evidence is reviewed.

### 28. Run the read-only Batch 2 database and provider quality audit

Run this only after Step 27 reports all 623 chunks complete, zero failed or rejected rows, 149636 accepted
rows, and `workerEnabled=False`. The audit is bound to the reviewed Batch 2 creation and recovery reports.

It first runs the database-only quality audit and saves the complete response. It then makes one paced,
read-only Upstox comparison for each of the 50 instruments and saves that response separately. It does not
import a candle, synchronize corporate actions, record a resolution, or prepare Batch 3.

After pulling the reviewed script on the spare laptop, run:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'

& '.\ops\windows\AuditReviewedExpansionBatch.ps1' `
    -JobId '7e8a79ec-045c-4474-b3e8-78e716e11143' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
```

Mandatory structural conditions are:

- the exact Batch 2 job remains `COMPLETED` with 50 instruments, 623 completed chunks, 149636 accepted rows,
  zero failed or rejected rows, and a disabled worker;
- `BlockingInstrumentCount=0`, `DuplicateRows=0`, `InvalidRows=0`, and `TruncatedFindingCount=0`;
- all 50 provider spot checks are `MATCHED`, with zero provider mismatches and check failures;
- database quality metrics do not change during the provider-backed read-only call;
- the job checkpoint is unchanged and both full JSON reports are saved under `C:\MarketBrainData\Review`.

`Status=REVIEW_REQUIRED` is expected when missing-session, calendar-gap, or large-move findings have not yet
been reviewed. It is not a structural failure. `Status=PASS` is possible only when no unresolved finding
remains and every provider comparison matches.

Share the complete summary, instrument-quality table, four finding tables, provider-check table, and eligibility
reasons. Do not synchronize corporate actions, add secondary candles, record exclusions or resolutions, or
prepare Batch 3 until the Step 28 evidence is reviewed.

### 29. Analyze every unresolved Batch 2 finding in one read-only plan

Run this only after Step 28 reports the reviewed Batch 2 checkpoint: 149636 candles, zero blocking instruments,
duplicates, invalid rows, provider mismatches, provider check failures, or truncated findings; all 50 provider
checks matched; and the worker remained disabled.

This step analyzes all 515 unresolved findings in one request: 423 official special-session omissions, 71
peer-confirmed omissions, two coverage findings, and 19 large moves. Repeated missing sessions are summarized
by date or incident in the console, while the complete 515-item plan is written to JSON. The analysis can fetch
official NSE evidence, but it cannot write a candle, exclusion, remediation plan, or quality resolution.

After committing and pulling the reviewed script on the spare laptop, run:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'

& '.\ops\windows\AnalyzeReviewedExpansionBatch.ps1' `
    -JobId '7e8a79ec-045c-4474-b3e8-78e716e11143' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
```

The accepted result must report:

- `Status=COMPLETED`, `UnresolvedFindingCount=515`, and `CandidateCount=515`;
- 423 official-session, 71 peer-session, two coverage-gap, and 19 large-move findings;
- `KeepOpenCount=0` and `SourceFailureCount=0`;
- identical candle and resolution counts before and after, with `WorkerEnabled=False`;
- a 64-character `PlanHash` and a complete immutable plan saved under `C:\MarketBrainData\Review`.

`Status=REVIEW_REQUIRED` means the analysis remained read-only but at least one evidence source or proposed
action is incomplete. Share the output; do not apply a partial plan. Even when the status is `COMPLETED`, share
the entire summary before the application step. Step 30 must be bound to the reviewed Step 29 plan hash and its
actual recommendation counts, so do not run the old Batch 1 application script or prepare Batch 3.

### 30. Apply the reviewed Batch 2 plan through resumable checkpoints

The reviewed Step 29 plan completed with hash
`8c61857a5ba64acdf66f4de4f1d658ecbb80bd1ff582066f89d773317336bc96`. It contains 515 actions: 478
secondary-source candles, 18 feature exclusions, one provider adjustment, and 18 verified exchange moves.
All 95 source requests succeeded, and no item was left open.

Commit and pull the reviewed script, confirm the spare-laptop worktree is clean, and run exactly one application
command:

```powershell
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git status --short
git pull --ff-only
Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health'

& '.\ops\windows\ApplyReviewedExpansionBatchPlan.ps1' `
    -ReviewedBy 'Harshal Pande' `
    -JobId '7e8a79ec-045c-4474-b3e8-78e716e11143' `
    -ReviewedManifestHash '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8' `
    -ExpectedPlanHash '8c61857a5ba64acdf66f4de4f1d658ecbb80bd1ff582066f89d773317336bc96'
```

The endpoint re-derives the live plan before its first write and refuses a different hash. It stores the plan and
then applies each item in a separate durable checkpoint. If power, Wi-Fi, or the response fails, rerun the exact
same command with the same reviewer and hashes; completed items are retained and only failed or pending items
are attempted. Never construct, delete, or edit remediation rows manually.

The accepted terminal result is `COMPLETED` with 515 completed and zero pending or failed items, 478 secondary
candles ready, 149636 unchanged Upstox candles, 478 NSE BhavCopy candles, 150114 total candles, 515 written and
current resolutions, zero unresolved findings, a disabled worker, and `FinalProviderSpotCheckRequired=True`.

The 71 AWL official candles are retained under the separate NSE source. The conservative coverage resolution
also excludes the original provider-gap window from future feature and return generation; it does not delete
either source's raw candles. The CAMS pre-history exclusion contains no stored candle. The BPCL provider
adjustment preserves its raw candle and excludes only the reviewed transition date.

Share the complete Step 30 result, including any failed-checkpoint table. Do not rerun Step 29 with altered
inputs, perform the final audit manually, or prepare Batch 3 until Step 30 is reviewed.

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
