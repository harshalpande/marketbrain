import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import ts from 'typescript'

// Compile only the pure contract module; no API, Docker or model execution.
const source = readFileSync(new URL('../src/paperAccount.ts', import.meta.url), 'utf8')
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText
const { parseOverview, formatInr } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`)
const valid = () => ({ version: 'PAPER_ACCOUNT_OVERVIEW_V1', status: 'READ_ONLY_EXECUTION_BLOCKED', currency: 'INR',
  observedAtUtc: '2026-10-09T00:00:00Z', account: { id: '1', name: 'Saved account', executionMode: 'PAPER', startingCash: '100000.00', currentCash: '90000.25' },
  activeAccountsObserved: 1, activeAccountCountIsLowerBound: false, legacyOrdersPresent: true, legacyFillsPresent: true,
  migrationAssessment: 'REVIEW_REQUIRED', blockers: ['A', 'B', 'C'], databaseWritesPerformed: false, actionExecutionEnabled: false, liveExecutionEnabled: false })
test('stored balances are preserved', () => assert.equal(parseOverview(valid()).account.currentCash, '90000.25'))
test('exact large monetary formatting', () => assert.equal(formatInr('9999999999999999.99'), '₹9,99,99,99,99,99,99,999.99'))
test('normal rupees', () => assert.equal(formatInr('100000'), '₹1,00,000.00'))
for (const field of ['databaseWritesPerformed', 'actionExecutionEnabled', 'liveExecutionEnabled']) {
  test(`reject enabled ${field}`, () => assert.throws(() => parseOverview({ ...valid(), [field]: true })))
}
for (const amount of ['NaN', '-1.00', '1.001', '1e5', 100000]) {
  test(`reject invalid money ${amount}`, () => assert.throws(() => parseOverview({ ...valid(), account: { ...valid().account, currentCash: amount } })))
}
test('missing account not manufactured', () => assert.equal(parseOverview({ ...valid(), account: null, activeAccountsObserved: 0 }).account, null))
test('ambiguous accounts not selected', () => assert.equal(parseOverview({ ...valid(), account: null, activeAccountsObserved: 2, activeAccountCountIsLowerBound: true }).account, null))
test('inconsistent account count rejected', () => assert.throws(() => parseOverview({ ...valid(), activeAccountsObserved: 0 })))
test('missing response rejected', () => assert.throws(() => parseOverview(null)))
test('wrong version rejected', () => assert.throws(() => parseOverview({ ...valid(), version: 'NEXT' })))
test('bad timestamp rejected', () => assert.throws(() => parseOverview({ ...valid(), observedAtUtc: 'unknown' })))
