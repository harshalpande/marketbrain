import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import ts from 'typescript'

// Compile only the pure contract module; no API, Docker or model execution.
const source = readFileSync(new URL('../src/paperAccount.ts', import.meta.url), 'utf8')
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText
const { parseOverview, formatInr } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`)
const valid = () => ({ version: 'PAPER_ACCOUNT_OVERVIEW_V2', status: 'READ_ONLY_EXECUTION_BLOCKED', currency: 'INR',
  observedAtUtc: '2026-10-09T00:00:00Z', account: { id: '1', name: 'Saved account', executionMode: 'PAPER', startingCash: '100000.00', currentCash: '90000.25' },
  activeAccountsObserved: 1, activeAccountCountIsLowerBound: false, legacyOrdersPresent: true, legacyFillsPresent: true,
  ledger: {status:'NOT_ATTACHED',cash:null,reservedCash:null,unreservedCash:null,revision:null},
  migrationAssessment: 'REVIEW_REQUIRED', blockers: ['APPLICATION_LEDGER_MIGRATION_PENDING', 'AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING', 'FILL_COST_AND_PNL_POLICY_PENDING'], databaseWritesPerformed: false, actionExecutionEnabled: false, liveExecutionEnabled: false })
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
const attached = () => ({...valid(), account:{id:'1',name:'Default Paper Portfolio',executionMode:'PAPER',startingCash:'100000.00',currentCash:'100000.00'},
  legacyOrdersPresent:false,legacyFillsPresent:false,migrationAssessment:'LEDGER_ATTACHED_READ_ONLY',blockers:valid().blockers.slice(1),
  ledger:{status:'ATTACHED_READ_ONLY',cash:'100000.00',reservedCash:'0.00',unreservedCash:'100000.00',revision:'0'}})
test('verified opening ledger parses',()=>assert.equal(parseOverview(attached()).ledger.unreservedCash,'100000.00'))
for(const field of ['cash','reservedCash','unreservedCash','revision']) {
  test(`corrupt ledger ${field} rejected`,()=>assert.throws(()=>parseOverview({...attached(),ledger:{...attached().ledger,[field]:'1'}})))
}
test('missing ledger rejected',()=>assert.throws(()=>parseOverview({...valid(),ledger:undefined})))
test('withheld state cannot expose balances',()=>assert.throws(()=>parseOverview({...valid(),ledger:{...valid().ledger,cash:'100000.00'}})))
test('ledger cannot hide legacy trades',()=>assert.throws(()=>parseOverview({...attached(),legacyOrdersPresent:true})))
test('unknown account cannot use ledger baseline',()=>assert.throws(()=>parseOverview({...attached(),account:{...attached().account,id:'2'}})))
test('release gates cannot disappear',()=>assert.throws(()=>parseOverview({...attached(),blockers:[]})))
