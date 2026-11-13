// Writes to the shared Supabase database through its REST API.
// Uses the service key, which lives only in GitHub Secrets, never in the app.

import { SafeError, errorCode } from './safe.js';

export function makeStore(env = process.env, fetchImpl = fetch) {
  // Accept the address with or without the "/rest/v1" ending that the dashboard shows.
  const url = (env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '').replace(/\/rest\/v1$/, '');
  const key = env.SUPABASE_SERVICE_KEY ?? '';
  if (!url || !key) return null;

  async function post(table, rows, { upsert = false } = {}) {
    if (!rows.length) return;
    const query = upsert ? '?on_conflict=id' : '';
    for (let i = 0; i < rows.length; i += 500) {
      const res = await fetchImpl(`${url}/rest/v1/${table}${query}`, {
        method: 'POST',
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          'Content-Type': 'application/json',
          Prefer: upsert ? 'resolution=merge-duplicates,return=minimal' : 'return=minimal',
        },
        body: JSON.stringify(rows.slice(i, i + 500)),
      });
      if (!res.ok) {
        // The answer may quote the row that failed, so only its status and its code go on.
        const code = errorCode(await res.text().catch(() => ''));
        throw new SafeError(`Supabase ${table}: HTTP ${res.status}${code ? ` ${code}` : ''}`);
      }
    }
  }

  return {
    saveTransactions: (rows) => post('bank_transactions', rows.map((r) => ({ ...r, synced_at: new Date().toISOString() })), { upsert: true }),
    saveBalances: (rows) => post('account_balances', rows.map((r) => ({ ...r, as_of: new Date().toISOString() }))),
    saveRun: (run) => post('sync_runs', [run]),
  };
}
