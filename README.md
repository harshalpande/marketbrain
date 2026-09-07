# MarketBrain

MarketBrain is a personal, self-hosted Indian-market research and paper-trading platform.

## Current phase

Phase 1 establishes the data-first foundation. It is deliberately paper-only:

- real market data may be collected and analysed;
- all portfolios and fills are virtual in `PAPER` mode;
- the risk engine must approve every actionable signal;
- no broker order placement is implemented;
- Telegram remains disabled until a private bot token and local pairing code are configured.

The reviewed NIFTY 500 historical foundation is complete, provider-audited, and backed up. The current increment adds governed daily enrichment: a read-only per-instrument freshness preview, deterministic reviewed manifest, bounded catch-up protection, resumable incremental jobs, and a disabled-by-default post-market scheduler. Once explicitly activated, it silently probes Upstox's current-day intraday daily endpoint from 16:00 India time and starts only after the target date is available, retrying every 15 minutes through 17:45 with one final attempt at 18:00. The worker combines the intraday target candle with historical catch-up dates under the same validation and normalization rules. It never rewrites review decisions and sends one private, action-free Telegram completion immediately after success or one warning only after the final 18:00 attempt fails. Transient connectivity/provider outages pause safely with persisted 1, 5, and 15 minute backoff and automatic continuation. Stale data remains non-actionable, and the system still cannot create a real broker order.

## Repository layout

| Path | Purpose |
| --- | --- |
| `marketbrain-service` | Spring Boot modular-monolith backend, database migrations, data-provider contracts, and risk/audit foundation. |
| `marketbrain-ui` | React and TypeScript dashboard with a persistent PAPER MODE indicator. |
| `compose.yaml` | Local container topology. PostgreSQL and Ollama remain native Windows services for this installation. |
| `docs` | Product and operating decisions that guide future implementation. |

## Local prerequisites

- Java 21 or newer
- Maven 3.9 or newer
- Node.js 22 or newer
- PostgreSQL 18 running locally with the `marketbrain` database

The backend reads database credentials only from environment variables. Never commit credentials, Telegram bot tokens, Analytics Tokens, Paytm tokens, or broker passwords.

For Upstox and Paytm Money feasibility details and the Nifty 500 import format, see [data-provider-feasibility.md](docs/data-provider-feasibility.md).

For daily build, deployment, verification, and troubleshooting commands, use [daily-runbook.md](docs/daily-runbook.md).

## Run locally

Backend:

```powershell
cd marketbrain-service
$env:MARKETBRAIN_DB_URL = 'jdbc:postgresql://127.0.0.1:5432/marketbrain'
$env:MARKETBRAIN_DB_USERNAME = 'marketbrain_app'
$env:MARKETBRAIN_DB_PASSWORD = '<your local password>'
mvn spring-boot:run
```

Dashboard:

```powershell
cd marketbrain-ui
npm install
npm run dev
```

Open `http://127.0.0.1:5173`. The dashboard is intentionally a PAPER MODE shell until the data and paper-trading workflows are connected.
