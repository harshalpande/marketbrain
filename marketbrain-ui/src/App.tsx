import { useEffect, useRef, useState } from 'react'
import { parseOverview, formatInr } from './paperAccount'
import type { Overview } from './paperAccount'

export default function App() {
  const [token, setToken] = useState('')
  const [overview, setOverview] = useState<Overview | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const request = useRef<AbortController | null>(null)
  useEffect(() => () => request.current?.abort(), [])

  function lock() {
    request.current?.abort(); request.current = null
    setToken(''); setOverview(null); setError(''); setLoading(false)
  }

  async function refresh() {
    request.current?.abort()
    const current = new AbortController()
    request.current = current
    setLoading(true); setError(''); setOverview(null)
    const timeout = window.setTimeout(() => current.abort(), 20000)
    try {
      const response = await fetch('/api/v1/paper/account/overview', {
        headers: { 'X-MarketBrain-Paper-Read-Token': token },
        cache: 'no-store', signal: current.signal, redirect: 'error',
      })
      if (!response.ok) throw new Error(response.status === 401
        ? 'Read token was not accepted.' : 'Account service unavailable or read access disabled. No action performed.')
      const result = parseOverview(await response.json())
      if (request.current === current) setOverview(result)
    } catch (failure) {
      if (request.current === current) setError(current.signal.aborted
        ? 'Read timed out. No automatic retry; retry manually when ready.'
        : failure instanceof Error ? failure.message : 'Unable to read account.')
    } finally {
      window.clearTimeout(timeout)
      if (request.current === current) { request.current = null; setLoading(false) }
    }
  }

  const account = overview?.account
  return (
    <main className="shell">
      <section className="mode-banner" aria-label="Current execution mode">
        <span className="mode-dot" /><strong>PAPER MODE · READ ONLY</strong>
        <span>No approval, order, fill or live execution is available here.</span>
      </section>
      <header className="hero">
        <div><p className="eyebrow">PAPER ACCOUNT INTEGRATION</p><h1>MarketBrain</h1>
          <p className="subheading">Your existing virtual account. Real stored balances, no sample trades.</p></div>
        <div className="status-chip">Phase 1 · Account visibility</div>
      </header>
      <section className="panel access-panel" aria-label="Read-only access">
        <form onSubmit={event => { event.preventDefault(); void refresh() }}>
          <label htmlFor="read-token">Private paper read token</label>
          <input id="read-token" type="password" value={token} autoComplete="off" minLength={32} maxLength={128}
            pattern="[A-Za-z0-9_-]{32,128}" required disabled={loading}
            onChange={event => { setToken(event.target.value); setOverview(null); setError('') }} />
          <button type="submit" disabled={loading}>{loading ? 'Reading…' : 'Read / refresh account'}</button>
          <button type="button" onClick={lock}>Clear and lock</button>
        </form>
        <p>Use only on this laptop or an approved private connection. Token stays in page memory, not browser storage.</p>
        {error && <p role="alert">{error}</p>}
        <p role="status">{loading ? 'Reading one database snapshot…' : overview
          ? `Snapshot observed: ${overview.observedAtUtc}. Not a live price feed.` : 'Locked or unavailable — no balance assumed.'}</p>
      </section>
      <section className="metric-grid" aria-label="Stored account balances">
        <article className="metric-card"><p>Starting cash</p><strong>{account ? formatInr(account.startingCash) : '—'}</strong><span>Stored value; never reseeded</span></article>
        <article className="metric-card"><p>Current recorded cash</p><strong>{account ? formatInr(account.currentCash) : '—'}</strong><span>Not verified buying power</span></article>
        <article className="metric-card"><p>Available / reserved cash</p><strong>Not integrated</strong><span>Ledger integration pending</span></article>
        <article className="metric-card"><p>Portfolio P&amp;L</p><strong>Not calculated</strong><span>Holdings and valuation pending</span></article>
      </section>
      <section className="content-grid">
        <article className="panel"><h2>Account and migration review</h2>
          {overview ? <>
            <p>{account ? `${account.name} · Account ${account.id}` : 'No unique active account. Manual review required.'}</p>
            <p>Active accounts observed: {overview.activeAccountsObserved}{overview.activeAccountCountIsLowerBound ? '+' : ''}</p>
            <p>Legacy orders: {overview.legacyOrdersPresent ? 'Present' : 'None found'} · Legacy fills: {overview.legacyFillsPresent ? 'Present' : 'None found'}</p>
            <p>Migration assessment: {overview.migrationAssessment.replaceAll('_', ' ')}</p>
            <ul>{overview.blockers.map(item => <li key={item}>{item.replaceAll('_', ' ')}</li>)}</ul>
          </> : <p>Read the account to inspect stored state. Missing data is never replaced with demo values.</p>}
        </article>
        <aside className="panel guardrail-panel"><h2>Next integration gates</h2><ol>
          <li>Preserve existing cash and history through reviewed ledger migration.</li>
          <li>Bind each approval to fresh quotes, account state and risk checks.</li>
          <li>Validate simulated fills, costs and P&amp;L before the paper pilot.</li>
        </ol></aside>
      </section>
    </main>
  )
}
