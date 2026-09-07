// Verdict policy for the CI selftest harness — pure and side-effect-free.
// The browser engine (ci-selftest.mjs) feeds polled document.title values in;
// this module alone decides whether they form a final verdict.
//
// Verdict shape: { ok: true, count, total } | { ok: false, reason[, count, total] }

// The app's selftest caps are ~4s worker + ~4s SW checks; a plain title that
// has not changed for this long means the selftest is not running -> FAIL.
export const EARLY_EXIT_MS = 12000;

// Single constructor for failure verdicts (one shape, one place).
export function fail(reason) {
  return { ok: false, reason };
}

export function parseSelftest(title) {
  const m = /^SELFTEST (\d+)\/(\d+)$/.exec(String(title ?? '').trim());
  if (!m) return fail('no selftest marker');
  const count = Number(m[1]);
  const total = Number(m[2]);
  if (total < 1) return fail('selftest ran 0 checks'); // 0/0 must never pass
  if (count !== total) {
    return { ok: false, count, total, reason: `${count}/${total} checks passed` };
  }
  return { ok: true, count, total };
}

// Poll decision: is this polled title a final verdict?
// done=true only for a real SELFTEST title (pass, partial, or empty run) or a
// plain title unchanged for EARLY_EXIT_MS (the selftest is not running).
export function classifyTitle(title, prevTitle, sinceChangeMs) {
  const p = parseSelftest(title);
  // A matched SELFTEST title is always a final verdict; only the no-marker
  // case can stay pending / go stable.
  if (p.reason !== 'no selftest marker') return { done: true, verdict: p };
  if (prevTitle !== null && title === prevTitle && sinceChangeMs >= EARLY_EXIT_MS) {
    return { done: true, verdict: fail(`no selftest marker (title unchanged for ${EARLY_EXIT_MS}ms)`) };
  }
  return { done: false };
}