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

Create—but do not start—the first 50-stock expansion batch:

```powershell
$batch = Invoke-RestMethod -Method Post `
    'http://127.0.0.1:8080/api/v1/market-data/backfills/nifty500/next-batch?years=15&batchSize=50'

$batch | Select-Object batchNumber, selectedInstruments, remainingInstrumentsAfterBatch, maximumBatchSize, detail | Format-List
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
