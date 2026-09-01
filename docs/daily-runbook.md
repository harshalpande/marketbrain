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
```

Do not add a Paytm token yet. We will enable it only for a deliberately small, read-only feasibility check.

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

## Runbook maintenance rule

For every future MarketBrain change that affects building, configuration, Docker deployment, verification, or safe operation, this document will be updated in the same code change.
