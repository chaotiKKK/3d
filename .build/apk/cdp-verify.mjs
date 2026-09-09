// Throwaway on-device verification driver — evaluates one async JS expression
// in the app's WebView over the adb-forwarded DevTools socket and prints the
// JSON result. Not part of the tested harness surface.
// Usage: node .build/apk/cdp-verify.mjs '<js-expression>'
const list = await (await fetch('http://127.0.0.1:9222/json/list')).json();
const ws = new WebSocket(list[0].webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
const expr = process.argv[2];
const send = (id, method, params) => ws.send(JSON.stringify({ id, method, params }));
const result = await new Promise((res) => {
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id === 1) res(m);
  };
  send(1, 'Runtime.evaluate', {
    expression: `(async () => { ${expr} })()`,
    awaitPromise: true,
    returnByValue: true,
  });
  setTimeout(() => res({ timeout: true }), 20000);
});
ws.close();
const v = result.result?.result;
console.log(JSON.stringify(v?.value ?? v?.description ?? v ?? result, null, 1));
process.exit(0);
