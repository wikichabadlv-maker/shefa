// Which accounts to sync, read from environment variables (GitHub Secrets).
// Nothing here is ever logged: only the account label and company are.

const COMPANIES = {
  DISCOUNT: { companyId: 'discount', label: 'דיסקונט', fields: { id: 'ID', password: 'PASSWORD', num: 'NUM' } },
  MAX: { companyId: 'max', label: 'מקס', fields: { username: 'USERNAME', password: 'PASSWORD' } },
  CAL: { companyId: 'visaCal', label: 'כאל', fields: { username: 'USERNAME', password: 'PASSWORD' } },
};

// Each company may appear more than once (e.g. one card per spouse):
// MAX_USERNAME / MAX_PASSWORD, then MAX_2_USERNAME / MAX_2_PASSWORD, up to _4.
const SLOTS = ['', '_2', '_3', '_4'];

export function readAccounts(env = process.env) {
  const accounts = [];
  const problems = [];
  for (const [prefix, company] of Object.entries(COMPANIES)) {
    for (const slot of SLOTS) {
      const credentials = {};
      const missing = [];
      for (const [field, suffix] of Object.entries(company.fields)) {
        const value = (env[`${prefix}${slot}_${suffix}`] ?? '').trim();
        if (value) credentials[field] = value;
        else missing.push(`${prefix}${slot}_${suffix}`);
      }
      const given = Object.keys(credentials).length;
      if (given === 0) continue;
      const key = `${company.companyId}${slot}`;
      if (missing.length) {
        problems.push(`${company.label}${slot ? ` (${slot.slice(1)})` : ''}: חסרים ${missing.join(', ')}`);
        continue;
      }
      accounts.push({
        key,
        companyId: company.companyId,
        label: slot ? `${company.label} ${slot.slice(1)}` : company.label,
        credentials,
      });
    }
  }
  return { accounts, problems };
}
