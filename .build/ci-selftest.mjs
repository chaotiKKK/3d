// CI selftest harness — dependency-free (Node built-ins only).
// Usage: node .build/ci-selftest.mjs <http(s)-url>   (exit 0 = all checks passed)
//
// The app's ?selftest is an async boot IIFE (zip round-trip, worker parity,
// SW registration/activation) that sets document.title only when finished —
// always AFTER the load event, so a one-shot --dump-dom can never see it.
// We keep the page alive and poll document.title in real time over the
// DevTools Protocol (Node >= 22 has a built-in WebSocket client).
//
// Structure: this module is the browser engine + CLI. All verdict policy
// (what makes a title a PASS/FAIL) lives in verdict.mjs — pure and tested.
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { classifyTitle, fail } from './verdict.mjs';

// Known headless-capable browsers: this environment's Edge first (AGENTS.md),
// then GitHub-hosted runner / typical Linux & macOS paths.
const BROWSERS = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
];

const TITLE_TIMEOUT_MS = 30000;
const TARGET_TIMEOUT_MS = 20000;
const POLL_MS = 300;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function freePort() {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => {
      const p = s.address().port;
      s.close(() => resolve(p));
    });
  });
}

async function findPageTarget(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await res.json();
      const page = targets.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch { /* DevTools not up yet */ }
    await sleep(200);
  }
  throw new Error('DevTools endpoint not reachable');
}

// One CDP request at a time (the poll loop is sequential): resolve with the
// response, or with null if the connection dies first so the loop can bail
// out. `closed` is a single per-connection promise — no per-send listeners.
function send(ws, closed, id, method, params) {
  return new Promise((resolve) => {
    const handler = (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.id === id) {
        ws.removeEventListener('message', handler);
        resolve(msg);
      }
    };
    ws.addEventListener('message', handler);
    closed.then(() => {
      ws.removeEventListener('message', handler);
      resolve(null);
    });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function waitForTitle(wsUrl, timeoutMs) {
  const ws = new WebSocket(wsUrl);
  // undici's WebSocket throws on send() while CONNECTING — wait for open.
  const connected = await new Promise((resolve) => {
    ws.addEventListener('open', () => resolve(true), { once: true });
    ws.addEventListener('error', () => resolve(false), { once: true });
    ws.addEventListener('close', () => resolve(false), { once: true });
  });
  if (!connected) return fail('devtools connection failed');
  const deadline = Date.now() + timeoutMs;
  const closed = new Promise((resolve) => {
    ws.addEventListener('close', () => resolve(), { once: true });
    ws.addEventListener('error', () => resolve(), { once: true });
  });
  let lastTitle = null;
  let sinceChange = Date.now();
  let id = 0;
  while (Date.now() < deadline) {
    // Race the CDP request against the remaining budget: a hung renderer or
    // dead target must not outlive the advertised timeout.
    const msg = await Promise.race([
      send(ws, closed, ++id, 'Runtime.evaluate', {
        expression: 'document.title',
        returnByValue: true,
      }),
      sleep(deadline - Date.now()),
    ]);
    if (msg === undefined) return fail(`timeout after ${timeoutMs}ms (title=${JSON.stringify(lastTitle)})`);
    if (msg === null) return fail('devtools connection closed');
    const title = String((msg.result && msg.result.result ? msg.result.result.value : '') ?? '').trim();
    if (title !== lastTitle) { lastTitle = title; sinceChange = Date.now(); }
    const c = classifyTitle(title, lastTitle, Date.now() - sinceChange);
    if (c.done) return c.verdict;
    await sleep(POLL_MS);
  }
  return fail(`timeout after ${timeoutMs}ms (title=${JSON.stringify(lastTitle)})`);
}

async function main() {
  const url = process.argv[2];
  if (!url || !/^https?:\/\//.test(url)) {
    console.error('usage: node .build/ci-selftest.mjs <http(s)-url>');
    process.exit(2);
  }
  const browser = BROWSERS.find((p) => existsSync(p));
  if (!browser) {
    console.error('[ci-selftest] no known browser found on this machine');
    process.exit(2);
  }
  const profileDir = mkdtempSync(join(tmpdir(), 'ci-selftest-'));
  let child = null;
  try {
    const port = await freePort();
    child = spawn(
      browser,
      [
        '--headless=new',
        '--no-first-run',
        '--no-default-browser-check',
        '--remote-allow-origins=*',
        `--user-data-dir=${profileDir}`,
        `--remote-debugging-port=${port}`,
        url,
      ],
      { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore'] },
    );
    const target = await findPageTarget(port, TARGET_TIMEOUT_MS);
    const verdict = await waitForTitle(target.webSocketDebuggerUrl, TITLE_TIMEOUT_MS);
    if (verdict.ok) {
      console.log(`[ci-selftest] PASS ${verdict.count}/${verdict.total}`);
      process.exitCode = 0;
    } else {
      console.error(`[ci-selftest] FAIL (${verdict.reason})`);
      process.exitCode = 1;
    }
  } finally {
    if (child && !child.killed) { try { child.kill(); } catch { /* ignore */ } }
    // Windows: Edge's child processes hold the profile dir for a moment after
    // kill(); cleanup must never override the verdict's exit code, so retry
    // and give up silently rather than throw.
    for (let i = 0; i < 5; i++) {
      try {
        rmSync(profileDir, { recursive: true, force: true });
        break;
      } catch {
        await sleep(400);
      }
    }
  }
}

// Entry point only — nothing imports this module (the tested surface is
// verdict.mjs), so no import-guard indirection is needed.
main().catch((e) => {
  console.error(`[ci-selftest] ERROR: ${e.message}`);
  process.exit(2);
});