// What may be written to the log about a failure. The Actions log can be read by anyone who
// can read the repository, so nothing that came from a bank, from the database or from a web
// page is ever copied into it: a failure is described by its kind alone.

/** An error whose message was put together here, from fixed words and a status alone. */
export class SafeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'SafeError';
  }
}

const KINDS = [
  [/timeout|timed out/i, 'timeout'],
  [/net::|ECONN|ENOTFOUND|EAI_AGAIN|ETIMEDOUT|socket|network|fetch failed/i, 'network'],
  [/selector|waiting for|element/i, 'page changed'],
  [/navigat|frame|target closed|session closed|detached|browser/i, 'browser'],
];

/** A few fixed words about an error: its class, and its kind when one is recognized. */
export function describeError(err) {
  if (err instanceof SafeError) return err.message;
  const name = typeof err?.name === 'string' && /^[A-Za-z]{1,40}$/.test(err.name) ? err.name : 'Error';
  const text = String(err?.message ?? err ?? '');
  const kind = KINDS.find(([pattern]) => pattern.test(text))?.[1];
  return kind ? `${name}, ${kind}` : name;
}

/** The code of a database error, when the answer carries one of the usual form. Nothing else of it. */
export function errorCode(body) {
  try {
    const code = JSON.parse(body)?.code;
    return typeof code === 'string' && /^[A-Za-z0-9]{3,10}$/.test(code) ? code : '';
  } catch {
    return '';
  }
}
