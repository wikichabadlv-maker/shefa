import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeResult, last4 } from '../src/normalize.js';
import { readAccounts } from '../src/config.js';

const tx = (over = {}) => ({
  type: 'normal', date: '2026-11-11T22:00:00.000Z', processedDate: '2026-12-02T00:00:00.000Z',
  originalAmount: -12, originalCurrency: 'ILS', chargedAmount: -12, description: '  ארומה  תל אביב ',
  status: 'completed', ...over,
});

test('identical purchases on one day get different ids, and a re-run gets the same ids', () => {
  const result = { accounts: [{ accountNumber: '4580-1234', txns: [tx(), tx()] }] };
  const a = normalizeResult(result, { sourceKey: 'max', companyId: 'max' }).rows;
  const b = normalizeResult(result, { sourceKey: 'max', companyId: 'max' }).rows;
  assert.equal(a.length, 2);
  assert.notEqual(a[0].id, a[1].id);
  assert.deepEqual(a.map((r) => r.id), b.map((r) => r.id));
});

test('dates are Israel days, text is cleaned, account is masked', () => {
  const [row] = normalizeResult({ accounts: [{ accountNumber: '4580-1234', txns: [tx()] }] },
    { sourceKey: 'max', companyId: 'max' }).rows;
  assert.equal(row.date, '2026-11-12');
  assert.equal(row.description, 'ארומה תל אביב');
  assert.equal(row.account, '1234');
  assert.equal(row.amount, -12);
});

test('installments keep their number and differ by id', () => {
  const rows = normalizeResult({ accounts: [{ accountNumber: '1', txns: [
    tx({ type: 'installments', installments: { number: 1, total: 3 } }),
    tx({ type: 'installments', installments: { number: 2, total: 3 } }),
  ] }] }, { sourceKey: 'visaCal', companyId: 'visaCal' }).rows;
  assert.equal(rows[1].installment_number, 2);
  assert.notEqual(rows[0].id, rows[1].id);
});

test('balances are collected when present', () => {
  const { balances } = normalizeResult({ accounts: [{ accountNumber: '12-345-678901', balance: 1520.456, txns: [] }] },
    { sourceKey: 'discount', companyId: 'discount' });
  assert.deepEqual(balances, [{ source: 'discount', account: '8901', balance: 1520.46 }]);
});

test('last4 handles odd account numbers', () => {
  assert.equal(last4('ABC'), 'ABC');
  assert.equal(last4('12/345'), '2345');
});

test('accounts are read from secrets, with partial ones reported', () => {
  const { accounts, problems } = readAccounts({
    DISCOUNT_ID: '1', DISCOUNT_PASSWORD: 'p', DISCOUNT_NUM: 'n',
    MAX_USERNAME: 'u', MAX_PASSWORD: 'p', MAX_2_USERNAME: 'u2', MAX_2_PASSWORD: 'p2',
    CAL_USERNAME: 'only-user',
  });
  assert.deepEqual(accounts.map((a) => a.key), ['discount', 'max', 'max_2']);
  assert.deepEqual(accounts[0].credentials, { id: '1', password: 'p', num: 'n' });
  assert.equal(problems.length, 1);
  assert.match(problems[0], /CAL_PASSWORD/);
});
