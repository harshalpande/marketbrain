import { paperDashboardPreview } from './dashboard'

const metricCards = [
  { label: 'Paper capital', value: '₹1,00,000', detail: 'Virtual only' },
  { label: 'Actionable signals', value: '0', detail: 'No provider connected' },
  { label: 'Open paper positions', value: '0', detail: 'PAPER MODE' },
  { label: 'Data health', value: 'Pending', detail: 'Provider validation required' },
]

export default function App() {
  return (
    <main className="shell">
      <section className="mode-banner" aria-label="Current execution mode">
        <span className="mode-dot" />
        <strong>PAPER MODE</strong>
        <span>Virtual capital. No Paytm Money order can be created.</span>
      </section>

      <header className="hero">
        <div>
          <p className="eyebrow">PERSONAL MARKET RESEARCH</p>
          <h1>MarketBrain</h1>
          <p className="subheading">Data-first signals, risk-aware paper trading, and an auditable decision timeline.</p>
        </div>
        <div className="status-chip">Foundation in progress</div>
      </header>

      <section className="metric-grid" aria-label="Paper mode overview">
        {metricCards.map((metric) => (
          <article className="metric-card" key={metric.label}>
            <p>{metric.label}</p>
            <strong>{metric.value}</strong>
            <span>{metric.detail}</span>
          </article>
        ))}
      </section>

      <section className="content-grid">
        <article className="panel signal-panel">
          <div className="panel-heading">
            <div>
              <p className="eyebrow">SIGNAL TIMELINE</p>
              <h2>What needs your attention</h2>
            </div>
            <span className="quiet-label">No alert noise</span>
          </div>

          <div className="signal-list">
            {paperDashboardPreview.map((signal) => (
              <article className="signal-row" key={signal.id}>
                <span className={`signal-type ${signal.label.toLowerCase()}`}>{signal.label}</span>
                <div>
                  <strong>{signal.symbol}</strong>
                  <p>{signal.detail}</p>
                </div>
                <time>{signal.timestamp}</time>
              </article>
            ))}
          </div>
        </article>

        <aside className="panel guardrail-panel">
          <p className="eyebrow">NON-NEGOTIABLE GUARDRAILS</p>
          <h2>Every future action is checked twice.</h2>
          <ol>
            <li>Data freshness must be within 90 seconds.</li>
            <li>Reference price becomes a valid price zone, never an exact-price demand.</li>
            <li>Risk revalidation happens immediately before every paper fill.</li>
            <li>Telegram approval creates a virtual trade only.</li>
          </ol>
        </aside>
      </section>
    </main>
  )
}
