export interface Overview {
  version: 'PAPER_ACCOUNT_OVERVIEW_V1'
  status: 'READ_ONLY_EXECUTION_BLOCKED'
  currency: 'INR'
  observedAtUtc: string
  account: null | { id: string; name: string; executionMode: string; startingCash: string; currentCash: string }
  activeAccountsObserved: number
  activeAccountCountIsLowerBound: boolean
  legacyOrdersPresent: boolean
  legacyFillsPresent: boolean
  migrationAssessment: 'EMPTY_ACCOUNT_REVIEWABLE' | 'REVIEW_REQUIRED'
  blockers: string[]
  databaseWritesPerformed: false
  actionExecutionEnabled: false
  liveExecutionEnabled: false
}

export function parseOverview(value: unknown): Overview {
  const x = value as Overview
  if (!x || x.version !== 'PAPER_ACCOUNT_OVERVIEW_V1' || x.status !== 'READ_ONLY_EXECUTION_BLOCKED'
      || x.currency !== 'INR' || x.databaseWritesPerformed !== false || x.actionExecutionEnabled !== false
      || x.liveExecutionEnabled !== false || typeof x.observedAtUtc !== 'string' || !Number.isFinite(Date.parse(x.observedAtUtc))
      || ![0, 1, 2].includes(x.activeAccountsObserved)
      || x.activeAccountCountIsLowerBound !== (x.activeAccountsObserved === 2)
      || typeof x.legacyOrdersPresent !== 'boolean' || typeof x.legacyFillsPresent !== 'boolean'
      || !['EMPTY_ACCOUNT_REVIEWABLE', 'REVIEW_REQUIRED'].includes(x.migrationAssessment)
      || !Array.isArray(x.blockers) || x.blockers.length < 3 || !x.blockers.every(b => typeof b === 'string')
      || (x.activeAccountsObserved === 1) !== (x.account !== null)) throw new Error('Unexpected account contract; view withheld.')
  if (x.account && (typeof x.account.id !== 'string' || !/^[1-9]\d*$/.test(x.account.id)
      || typeof x.account.name !== 'string' || typeof x.account.executionMode !== 'string'
      || !validAmount(x.account.startingCash) || !validAmount(x.account.currentCash))) {
    throw new Error('Invalid account amounts; view withheld.')
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
