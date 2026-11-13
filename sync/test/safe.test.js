import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SafeError, describeError, errorCode } from '../src/safe.js';
import { makeStore } from '../src/store.js';

test('an error is described by its class and kind, never by its own words', () => {
  const timeout = Object.assign(new Error('Navigation timeout of 60000 ms exceeded at https://bank.example/?id=123456789'),
    { name: 'TimeoutError' });
  assert.equal(describeError(timeout), 'TimeoutError, timeout');

  const plain = new Error('Unknown account 0123456789 of ישראל ישראלי');
  assert.equal(describeError(plain), 'Error');

  const network = new Error('net::ERR_CONNECTION_RESET at https://bank.example/login');
  assert.equal(describeError(network), 'Error, network');

  // A name that is not a plain class name is not trusted either.
  const odd = Object.assign(new Error('x'), { name: 'card 4580-1234' });
  assert.equal(describeError(odd), 'Error');

  assert.equal(describeError('a bare string with 4580-1234'), 'Error');
  assert.equal(describeError(undefined), 'Error');
});

test('an error put together here keeps its message', () => {
  assert.equal(describeError(new SafeError('Supabase sync_runs: HTTP 500')), 'Supabase sync_runs: HTTP 500');
});

test('only a code of the usual form is taken from a database answer', () => {
  assert.equal(errorCode('{"code":"23502","details":"Failing row contains (max:1234, -74.00, חנות הפינה)"}'), '23502');
  assert.equal(errorCode('{"code":"PGRST204","message":"Could not find the column"}'), 'PGRST204');
  assert.equal(errorCode('{"code":"4580 1234 5678"}'), '');
  assert.equal(errorCode('{"code":42}'), '');
  assert.equal(errorCode('<html>Bad gateway</html>'), '');
  assert.equal(errorCode(''), '');
});

test('a failed write says the table, the status and the code, and nothing of the row', async () => {
  const body = JSON.stringify({
    code: '23502',
    details: 'Failing row contains (max:4580-1234:2026-11-12, 1234, -74.00, חנות הפינה).',
    hint: null,
    message: 'null value in column "source" of relation "bank_transactions" violates not-null constraint',
  });
  const fetchImpl = async () => ({ ok: false, status: 400, text: async () => body });
  const store = makeStore({ SUPABASE_URL: 'https://db.example/rest/v1/', SUPABASE_SERVICE_KEY: 'k' }, fetchImpl);
  await assert.rejects(
    () => store.saveTransactions([{ id: 'max:4580-1234:2026-11-12', description: 'חנות הפינה', amount: -74 }]),
    (err) => {
      assert.ok(err instanceof SafeError);
      assert.equal(err.message, 'Supabase bank_transactions: HTTP 400 23502');
      assert.equal(describeError(err), 'Supabase bank_transactions: HTTP 400 23502');
      return true;
    },
  );
});

test('a failed write whose answer cannot be read still says only the status', async () => {
  const fetchImpl = async () => ({ ok: false, status: 502, text: async () => { throw new Error('socket hang up'); } });
  const store = makeStore({ SUPABASE_URL: 'https://db.example', SUPABASE_SERVICE_KEY: 'k' }, fetchImpl);
  await assert.rejects(() => store.saveRun({ source: 'max', ok: false }), (err) => {
    assert.equal(err.message, 'Supabase sync_runs: HTTP 502');
    return true;
  });
});

test('a write that succeeds sends the rows as before', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return { ok: true, status: 201, text: async () => '' };
  };
  const store = makeStore({ SUPABASE_URL: 'https://db.example', SUPABASE_SERVICE_KEY: 'k' }, fetchImpl);
  await store.saveTransactions([{ id: 'a' }, { id: 'b' }]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://db.example/rest/v1/bank_transactions?on_conflict=id');
  assert.equal(JSON.parse(calls[0].init.body).length, 2);
  assert.equal(calls[0].init.headers.Prefer, 'resolution=merge-duplicates,return=minimal');
});
