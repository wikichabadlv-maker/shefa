import { createHash } from 'node:crypto';

// Turns a scraper result into rows for the bank_transactions table.
// The id is deterministic, so re-running a sync updates rows instead of duplicating them.

const day = (iso) => (iso ? new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' }) : null);
const round2 = (n) => Math.round(Number(n) * 100) / 100;
const clean = (s) => (s ?? '').toString().replace(/\s+/g, ' ').trim();

export function last4(accountNumber) {
  const digits = clean(accountNumber).replace(/\D/g, '');
  return digits.slice(-4) || clean(accountNumber).slice(-4);
}

export function normalizeAccount(account, { sourceKey, companyId }) {
  const seen = new Map();
  const rows = [];
  for (const t of account.txns ?? []) {
    const date = day(t.date);
    const amount = round2(t.chargedAmount);
    const description = clean(t.description);
    // Without a bank reference number, two identical purchases on one day differ only by order.
    const base = [sourceKey, clean(account.accountNumber), date, amount, description, clean(t.identifier),
      t.installments ? `${t.installments.number}/${t.installments.total}` : ''].join('|');
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    const id = createHash('sha256').update(`${base}|${n}`).digest('hex').slice(0, 32);
    rows.push({
      id,
      source: sourceKey,
      company: companyId,
      account: last4(account.accountNumber),
      date,
      processed_date: day(t.processedDate),
      amount,
      original_amount: round2(t.originalAmount),
      original_currency: clean(t.originalCurrency) || 'ILS',
      description,
      memo: clean(t.memo) || null,
      status: t.status === 'pending' ? 'pending' : 'completed',
      installment_number: t.installments?.number ?? null,
      installment_total: t.installments?.total ?? null,
      bank_category: clean(t.category) || null,
      reference: t.identifier != null ? clean(t.identifier) : null,
    });
  }
  return rows;
}

export function normalizeResult(result, { sourceKey, companyId }) {
  const rows = [];
  const balances = [];
  for (const account of result.accounts ?? []) {
    rows.push(...normalizeAccount(account, { sourceKey, companyId }));
    if (typeof account.balance === 'number') {
      balances.push({ source: sourceKey, account: last4(account.accountNumber), balance: round2(account.balance) });
    }
  }
  return { rows, balances };
}
