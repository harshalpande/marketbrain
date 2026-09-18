# MarketBrain

Personal Indian-equity research and a planned **INR 100,000 paper-trading portal**. Live market data is allowed under reviewed provider access; real broker order execution is outside the current release.

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

The 2026-09-18 documentation reset changes documentation only. Earlier plans and experiments remain in [the explicitly superseded archive](docs/archive/2026-09-18/INDEX.md). No application build or deployment is required to receive this reset.
