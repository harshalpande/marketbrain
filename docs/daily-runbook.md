# MarketBrain daily runbook

This is the single operational guide for building, running, checking, and stopping MarketBrain. It is maintained with every deployable change.

## Safety boundary

- MarketBrain is currently **PAPER MODE only**. The application creates no real broker orders.
- Never commit `.env`, credentials, access tokens, passwords, or OTPs.
- PostgreSQL and Ollama run natively on the spare Windows laptop. Docker runs only the MarketBrain backend and dashboard.
- Docker services bind to `127.0.0.1` only. They are not publicly exposed and are not yet available from another device over Tailscale.

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

### 4. Validate and start Docker services

```powershell
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

The first start applies the versioned MarketBrain database migration. It adds MarketBrain tables and types to the existing `marketbrain` database; it does not change PostgreSQL itself and does not create any broker order.

### 5. Check the running application

```powershell
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
Invoke-RestMethod http://127.0.0.1:8080/api/v1/system/status
Invoke-RestMethod http://127.0.0.1:8080/api/v1/data-sources

Start-Process http://127.0.0.1:8081
```

Expected:

- health returns `UP`;
- system status reports `PAPER`;
- Paytm Money reports `DISABLED`;
- the dashboard shows a permanent PAPER MODE label.

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

## Runbook maintenance rule

For every future MarketBrain change that affects building, configuration, Docker deployment, verification, or safe operation, this document will be updated in the same code change.
