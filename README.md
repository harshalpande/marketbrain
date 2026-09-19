# MarketBrain

Personal Indian-equity research and a planned **INR 100,000 paper-trading portal**. Live market data is allowed under reviewed provider access; real broker order execution is outside the current release.

The two parent goals are a full trading-intelligence platform and its mandatory paper-first deployment: 15+ year history target, technical/fundamental/quantitative/news analysis, required 5/20/60-session forecasts plus separate intraday horizons, Telegram ACCEPT/REJECT, controlled feedback learning and eventually separately authorized Paytm execution. These are target capabilities, not a claim of implementation. See the canonical V2 baseline below.

## Start here

[Canonical documentation](docs/README.md) is the single entry point for scope, goals, evidence, timelines and daily progress.

- [Roadmap and completion dashboard](docs/roadmap.md)
- [System and paper-portal design](docs/system-design.md)
- [Evidence register and verification procedure](docs/evidence-register.md)
- [Daily progress and decision log](docs/daily-progress.md)

![Current target architecture and implementation boundaries](docs/marketbrain-architecture.svg)

## Current state

The Java service contains Upstox REST integration, historical/daily collection, technical snapshots, prototype outcome datasets, model-evaluation tools, and notification foundations. The React dashboard is a static preview. A trained numerical predictor, live streaming pipeline and complete paper-order lifecycle are not yet implemented. Source presence does not prove spare-laptop runtime readiness.

Development and offline verification take place here; model inference and deployment take place on the spare laptop. Credentials stay in ignored local configuration. Do not enable live execution or use archived deployment commands as current instructions.

The [ten-feature numerical engineering bundle](docs/numerical-ten-feature-engineering.md) passed 32/32 spare checks; this engineering checkpoint is complete. It is not a trained market predictor and does not lift the source/evaluation gates. The owner-approved [two-track preparation plan](docs/numerical-research-scope-decision.md) separates restricted retrospective research from prospective validation. No repeat bundle, service rebuild or LLM run is requested.

The 2026-09-18 documentation reset changes documentation only. Earlier plans and experiments remain in [the explicitly superseded archive](docs/archive/2026-09-18/INDEX.md). No application build or deployment is required to receive this reset.
