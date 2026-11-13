import { createRequire } from 'node:module';
import { readAccounts } from './config.js';
import { normalizeResult } from './normalize.js';
import { makeStore } from './store.js';
import { describeError } from './safe.js';

const require = createRequire(import.meta.url);
const { createScraper } = require('israeli-bank-scrapers');

// Logs only counts, dates and error types: the repository's Actions log must never hold
// passwords, account numbers or what was bought. An error's own words are never printed,
// since they may quote a page or a row: only its kind is.

// Whatever escapes is described in the same careful way, and ends the run as it did before.
process.on('uncaughtException', (err) => {
  console.log(`❌ תקלה שלא נתפסה – ${describeError(err)}`);
  process.exit(1);
});
process.on('unhandledRejection', (err) => {
  console.log(`❌ תקלה שלא נתפסה – ${describeError(err)}`);
  process.exit(1);
});

const days = Number(process.env.SYNC_DAYS) > 0 ? Number(process.env.SYNC_DAYS) : 45;
const startDate = new Date(Date.now() - days * 864e5);

const { accounts, problems } = readAccounts();
for (const p of problems) console.log(`⚠️  ${p}`);
if (!accounts.length) {
  console.log('לא הוגדרו חשבונות. ראו את ההוראות ב-README.');
  process.exit(1);
}

const store = makeStore();
if (!store) console.log('מסד הנתונים עוד לא מחובר: בדיקת חיבור בלבד, שום דבר לא נשמר.');

let failures = 0;
for (const account of accounts) {
  const started = Date.now();
  const run = { source: account.key, ran_at: new Date().toISOString(), ok: false, error_type: null, count: 0 };
  try {
    const scraper = createScraper({
      companyId: account.companyId,
      startDate,
      combineInstallments: false,
      showBrowser: false,
      defaultTimeout: 60000,
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    });
    const result = await scraper.scrape(account.credentials);
    if (!result.success) {
      run.error_type = result.errorType ?? 'UNKNOWN';
      throw new Error(run.error_type);
    }
    const { rows, balances } = normalizeResult(result, { sourceKey: account.key, companyId: account.companyId });
    run.ok = true;
    run.count = rows.length;
    const dates = rows.map((r) => r.date).filter(Boolean).sort();
    const pending = rows.filter((r) => r.status === 'pending').length;
    console.log(`✅ ${account.label}: ${result.accounts.length} חשבונות/כרטיסים, ${rows.length} תנועות` +
      (dates.length ? ` (${dates[0]} עד ${dates.at(-1)})` : '') +
      (pending ? `, ${pending} ממתינות` : '') +
      `, ${Math.round((Date.now() - started) / 1000)} שניות`);
    if (store) {
      await store.saveTransactions(rows);
      await store.saveBalances(balances);
    }
  } catch (err) {
    failures++;
    const generic = !run.error_type;
    run.error_type ??= 'GENERIC';
    console.log(`❌ ${account.label}: נכשל (${run.error_type})` +
      (generic ? ` – ${describeError(err)}` : ''));
  }
  if (store) await store.saveRun(run).catch(() => console.log('⚠️  לא נשמר רישום הריצה'));
}

process.exit(failures ? 1 : 0);
