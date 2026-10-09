export interface Overview {
  version: 'PAPER_ACCOUNT_OVERVIEW_V2'
  status: 'READ_ONLY_EXECUTION_BLOCKED'
  currency: 'INR'
  observedAtUtc: string
  account: null | { id: string; name: string; executionMode: string; startingCash: string; currentCash: string }
  activeAccountsObserved: number
  activeAccountCountIsLowerBound: boolean
  legacyOrdersPresent: boolean
  legacyFillsPresent: boolean
  migrationAssessment: 'EMPTY_ACCOUNT_REVIEWABLE' | 'REVIEW_REQUIRED' | 'LEDGER_ATTACHED_READ_ONLY'
  ledger: { status: 'NOT_ATTACHED' | 'REVIEW_REQUIRED' | 'ATTACHED_READ_ONLY'; cash: string | null;
    reservedCash: string | null; unreservedCash: string | null; revision: string | null }
  blockers: string[]
  databaseWritesPerformed: false
  actionExecutionEnabled: false
  liveExecutionEnabled: false
}

export function parseOverview(value: unknown): Overview {
  const x = value as Overview
  if (!x || x.version !== 'PAPER_ACCOUNT_OVERVIEW_V2' || x.status !== 'READ_ONLY_EXECUTION_BLOCKED'
      || x.currency !== 'INR' || x.databaseWritesPerformed !== false || x.actionExecutionEnabled !== false
      || x.liveExecutionEnabled !== false || typeof x.observedAtUtc !== 'string' || !Number.isFinite(Date.parse(x.observedAtUtc))
      || ![0, 1, 2].includes(x.activeAccountsObserved)
      || x.activeAccountCountIsLowerBound !== (x.activeAccountsObserved === 2)
      || typeof x.legacyOrdersPresent !== 'boolean' || typeof x.legacyFillsPresent !== 'boolean'
      || !['EMPTY_ACCOUNT_REVIEWABLE', 'REVIEW_REQUIRED', 'LEDGER_ATTACHED_READ_ONLY'].includes(x.migrationAssessment)
      || !Array.isArray(x.blockers) || !['AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING', 'FILL_COST_AND_PNL_POLICY_PENDING'].every(b => x.blockers.includes(b))
      || !x.blockers.every(b => typeof b === 'string')
      || (x.activeAccountsObserved === 1) !== (x.account !== null)) throw new Error('Unexpected account contract; view withheld.')
  if (x.account && (typeof x.account.id !== 'string' || !/^[1-9]\d*$/.test(x.account.id)
      || typeof x.account.name !== 'string' || typeof x.account.executionMode !== 'string'
      || !validAmount(x.account.startingCash) || !validAmount(x.account.currentCash))) {
    throw new Error('Invalid account amounts; view withheld.')
  }
  const l = x.ledger
  if (!l || !['NOT_ATTACHED', 'REVIEW_REQUIRED', 'ATTACHED_READ_ONLY'].includes(l.status)) throw new Error('Missing ledger state.')
  if (l.status === 'ATTACHED_READ_ONLY') {
    if (x.migrationAssessment !== 'LEDGER_ATTACHED_READ_ONLY' || !x.account || x.account.id !== '1'
        || x.account.name !== 'Default Paper Portfolio' || x.account.executionMode !== 'PAPER'
        || x.account.startingCash !== '100000.00' || x.account.currentCash !== '100000.00'
        || x.legacyOrdersPresent || x.legacyFillsPresent || l.cash !== x.account.currentCash
        || l.reservedCash !== '0.00' || l.unreservedCash !== '100000.00' || l.revision !== '0'
        || x.blockers.includes('APPLICATION_LEDGER_MIGRATION_PENDING')
        || x.blockers.includes('LEDGER_RECONCILIATION_REQUIRED')) throw new Error('Unverified ledger balances; view withheld.')
  } else if ([l.cash, l.reservedCash, l.unreservedCash, l.revision].some(v => v !== null)
      || x.migrationAssessment === 'LEDGER_ATTACHED_READ_ONLY'
      || !x.blockers.includes(l.status === 'NOT_ATTACHED' ? 'APPLICATION_LEDGER_MIGRATION_PENDING' : 'LEDGER_RECONCILIATION_REQUIRED')) {
    throw new Error('Inconsistent ledger state; view withheld.')
  }
  return x
}

function validAmount(value: unknown): value is string {
  return typeof value === 'string' && /^\d{1,16}(\.\d{1,2})?$/.test(value)
}

// Never round database monetary strings through JS floating point.
export function formatInr(value: string): string {
  if (!validAmount(value)) throw new Error('Invalid amount')
  const [rupees, fraction = ''] = value.split('.')
  return `₹${BigInt(rupees).toLocaleString('en-IN')}.${fraction.padEnd(2, '0')}`
}
