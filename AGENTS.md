# AGENTS.md

Project: **FreeCam3D** — single-file HTML stereo 3D scanner PWA.

## Where the code is
- The **deployable build lives in this project dir**: `index.html` (the whole app),
  `manifest.webmanifest`, `sw.js`, `icon-192.png`, `icon-512.png`, `README.md`.
- The original app source is `C:\Users\HP\Downloads\3d.html` (pre-fix, CRLF,
  contains bugs below). `index.html` is the fixed, LF-normalized working copy
  derived from it. The parallel `deepseek_html_*.html` variant = 3d.html PLUS a
  defensive `refreshDevices` — only that change; it is a **sibling** of
  `index.html`, not its ancestor (both derive independently from 3d.html, and a
  fix lives in only one until explicitly merged — diff all three when porting).
- Android PWA constraints (secure context, phone cam limits) are handled inside
  the app + documented in `README.md`.
- **Git repository (since 2026-09-03):** root commit `4cb41eb` (the four delivery
  files). Now tracked: the PWA shell (`manifest.webmanifest`, `sw.js`,
  `icon-*.png` — over HTTP the app is broken without it: `sw.js` 404 → selftest
  drops to 67/69), the CI harness (`.build/verdict.mjs`, `.build/verdict.test.mjs`,
  `.build/ci-selftest.mjs`), the APK build system (`.build/apk/` source only —
  `build-apk.sh` + `app/` manifest/MainActivity/res; `.build/apk/.gitignore`
  keeps the local `jdk/`, `android-sdk/`, `webkit/` jars, `build/`, and
  `debug.keystore` out),  and `.github/workflows/selftest.yml` + `.build/ui-smoke.py` (the
  Playwright UI smoke the workflow's `ui-smoke` job runs; pinned
  playwright==1.62.0). Still untracked: `desktop/` (abandoned Electron EXE
  scaffold), `.build/pw-venv` (local Playwright venv) + `.build/ui-shots/`
  (smoke screenshots), `FreeCam3D.apk` (build artifact — rebuild via the
  committed script), `.agents/`/`.tools/`, `selftest-result.png` — stage
  explicitly if needed; do not `git add -A`.

## Testing / verification
- `?selftest` URL param runs the pure-logic assertions (CRC32/ZIP round-trip,
  stereo matching, project schema, decoupled frameSource, …), writes a
  `SELFTEST n/n OK` banner and sets `document.title`; console logs
  `[selftest] ALL PASS`. 66 fixed pure-logic checks (incl. the polish helpers:
  onboarding step/progress rule, log-level classification, German guard-toast
  strings, capture-tick gain, scan recipes; plus the asset-handoff contract:
  `assessFrame` quality triage + `buildScanMeta` angle-type mapping) + the
  **gated** `worker:disp==mainthread` parity check (compares the Blob Web
  Worker's disparity to main-thread `rf2`, only asserted when the worker
  returns — non-flaky, like the SW checks) run in every context; +2 HTTP-only
  SW/cache checks → **69/69 over HTTP, 67/67 over `file://`** (the 2-check
  delta is exactly the SW/cache checks).
- **CI harness:** `node .build/ci-selftest.mjs <http(s)-url>` asserts the
  `SELFTEST n/n` title via CDP on a live headless page (Node ≥ 22 built-in
  WebSocket, dependency-free; exit 0/1). One-shot `--dump-dom` can NEVER
  verify this app: the selftest IIFE awaits zip/worker/SW activation and sets
  the title after the load event, and `--virtual-time-budget` fast-forwards
  the 4 s check timeouts past real-time SW activation (observed false
  negative 67/69). A fresh profile reaches 69/69 because `sw.js` precaches
  the shell at install with `skipWaiting`/`clients.claim`. On Windows the
  Edge profile dir is briefly locked after kill — cleanup retries must not
  override the verdict's exit code. Structure: verdict policy (parse/
  classify/early-exit) lives in `.build/verdict.mjs` (pure, tested via `node
  --test .build/verdict.test.mjs`); `ci-selftest.mjs` is engine+CLI and
  imports it (never vice versa). `.github/workflows/selftest.yml` depends on
  the harness — commit `.build/` or the workflow fails. Three Windows/load
  pitfalls fixed after they produced real hangs/orphans: the DevTools WebSocket
  must be closed after the verdict (an open socket keeps Node alive → process
  hangs after printing PASS); Edge launchers can exit early so `child.kill()`
  orphans the tree — kill by the `ci-selftest-` profile marker via PowerShell
  (`killByMarker`) instead of by PID; `findPageTarget`'s fetch and the WS
  handshake both need their own bounded timeouts.
- Over `file://` the service-worker/cache checks are silently skipped (gated on
  `location.protocol.startsWith('http')` + `sw.js` reachable). Serve over HTTP(S)
  to exercise them: `python -m http.server 8080` in this dir, then
  `http://localhost:8080/?selftest`; `pwa:cache-primed` expects a cache whose
  name starts with `freecam3d-` (matches `CACHE` in `sw.js`).
- **Dev staleness trap:** the SW runtime-caches every successful GET (incl. the
  exact `?selftest` URL) cache-first, and `python -m http.server` sends no
  Cache-Control → Chromium's heuristic HTTP cache can feed the SW's `fetch()` a
  stale body with zero server contact (`cache:'no-store'` doesn't bypass the SW).
  A green `SELFTEST n/n` can be the OLD build — confirm a boot-log marker or use
  `?selftest&v=…`. To force fresh: `caches.open(…).delete(url)` +
  `fetch(url,{cache:'reload'})`, or bump `CACHE` (first reload after a bump is
  often still stale — old SW serves it, new SW activates via skipWaiting; the
  second reload is fresh).
  Proven refresh recipe in a live tab: the SW caches per **exact request URL**
  (the document is cached under the URL it was fetched as), so navigate to a
  **never-used query param** — a cache miss by construction — after deleting the
  stale entries (`caches.open(CACHE).delete(url)` for each previously used URL)
  from inside `preview_evaluate`. Re-navigating the same URL replays the stale
  copy. Note `preview_logs` keeps console entries from stale loads, so trust
  `document.title`/banner over the console history.

## Android / PWA constraints
- Most Android phones **cannot open two `getUserMedia` camera streams at once**,
  so the app's headline live-stereo→depth feature does nothing on a phone.
  Handled: `frameSource(i)` prefers the live stream, else the last captured /
  file-loaded frame; single-cam users load two shifted images via
  *Load Frame L/R* and run stereo from the stored frames.
- Secure context required: camera, service worker, and install prompt need HTTPS
  or localhost — `file://` won't do.
- APK shell (index.html stays untouched): `bash .build/apk/build-apk.sh` builds
  `FreeCam3D.apk` at repo root from a project-local toolchain in `.build/apk/`
  (Temurin 17 + build-tools 34; hand-built aapt2→javac→d8→aapt add→zipalign→apksigner,
  no gradle; on Windows `d8`/`apksigner` must be called as `.bat`).
  WebViewAssetLoader serves assets at `https://appassets.androidplatform.net/assets/`
  (secure context → getUserMedia works). Exports ride an injected `downloadBlob(blob,fn)`
  override → `FreeCamNative.saveB64` → MediaStore Downloads (API ≥29) / app dir (≤28).
  WebView has no service worker → the in-APK selftest reads 67/69 (the 2 `pwa:` checks
  fail); expected, not a regression. `debug.keystore` is untracked — a regenerated
  one changes the signature, so older phone installs must be uninstalled first.

## Architecture notes (post-fix)
- **Depth pipeline is decoupled** from live video: `getGray`/`getRGB` take a
  `<video>` *or* canvas (`srcW`/`srcH` helpers), `computeDepth`/`exportPLY`/
  `exportOBJ`/`exportDepthMap`/`updateGL3D` all go through `frameSource(i)`.
- WebGL vertex shader sets `gl_PointSize=clamp(220.0/gl_Position.w,2.0,10.0)`;
  3D viewport is driven by **pointer events** (1 finger = orbit, 2 = pinch zoom);
  `touch-action:none` set on the canvases.
- Capture pipelines buffer blobs (`flushDownloads`) and hand out **one ZIP**
  (`zipBlobs`/`parseZip`, dependency-free: STORE + CompressionStream DEFLATE,
  CRC32 table, no external libs) instead of per-frame downloads.
- Shot images are kept in **IndexedDB** (`imgs` store, autoIncrement keys,
  `{n:name,b:blob,t:type}`) indexed by name in `blobByName`, capped at ~300
  entries via `evict()`. Export Project → ZIP (`project.json` + images);
  Restore Project accepts the ZIP (or legacy JSON) and re-persists blobs.
- The WebSocket rig block (startCams/takePhoto overrides + `connectWS`) is
  **deleted**; no auto-WS connect on load.
- **Orbit mode** (`toggleOrbit`) auto-tags Photo/Burst/Interval captures with the
  device heading via `DeviceOrientation` (prefers `deviceorientationabsolute`;
  iOS needs `requestPermission`). `captureMeta()` returns `{angle,imu:true}` where
  `angle=normAngle(heading−ref)`; the zero-`ref` is the heading when Orbit is
  switched on (tap the readout to re-zero). `normAngle` is pure/selftested. The
  angle is also prefixed to the capture filename (`a<deg>_…`). Turntable
  (`startTT`) is unaffected — it keeps its typed angles.
- Stereo matching runs in an **inline Blob Web Worker** (`getDepthWorker`) built
  from `stereoMatchRange`/`stereoCoarse`/`stereoRefine` via `.toString()` — one
  source of truth, still single-file/offline. `computeDepth` offloads to it and
  falls back to `computeDepthMain` (banded rAF) on worker failure; both share
  `finishDepth`. Selftest tests the pure functions directly on the main thread
  and adds one gated `worker:disp==mainthread` parity check.

## Gotchas when editing
- The file is one big `<script>`; keep it dependency-free (no npm/external libs).
- ZIP helpers assume no data descriptors and sizes from central-directory records
  (true for everything this app writes and for Explorer/`zip`-style writers);
  `CompressionStream('deflate-raw')` requires Chrome ≥ 80 — fallback is STORE.
- If you change the app's UI strings or capture filenames, keep the
  `blobByName` keying contract (shot `name` ↔ IDB record `n`) so Restore works.
- The capture toolbar (Photo/Record/Burst/3D View) lives in the **panel's first
  `.sec`**, not in `.previews` — a fix scoped to `.previews .btn-row` is a
  no-op. Mobile mode stacks the panel below the previews; `main` is the inner
  scroll container.
- Adding an `ok(...)` check to `?selftest` changes the documented totals in
  README.md (Selbsttest section) AND here (69/69, 67/67) — update all three
  together.
- index.html's top helper block (onboard*/tick*/dismissOnboard) grew through
  layered edit passes — a pass can leave BOTH an original and an improved copy
  of a function, and JS hoisting silently prefers the LAST duplicate (a stale
  `dismissOnboard` outlived its replacement this session). `grep -c 'function
  <name>'` before editing those helpers and delete superseded copies.
- SW runtime-cache must never `caches.put()` non-http(s) URLs: Edge routes
  internal extension requests (video-toolbar) through the page SW, and `put`
  rejects `chrome-extension:` with a TypeError even for 'basic'/'cors' responses.
  Guard on URL protocol (`/^https?:$/…`) AND `.catch(()=>{})` the put —
  best-effort writes must never reject.

## Browser automation (agent-browser) in this environment
- Chrome-for-Testing download (193 MB) times out near completion on this network.
  Workaround: drive system **Edge** (`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`) instead.
- agent-browser's default headless flag makes Edge exit instantly (exit 0,
  "no DevToolsActivePort"). Launch Edge with `--headless=new
  --remote-debugging-port=<port>` yourself, then `agent-browser connect <port>`.
- Git Bash mangles `/tmp/...` passed as a bare arg to node (resolves to
  `C:\tmp`), but not inside quoted JS strings — use `$TEMP` or quote paths.
- `agent-browser eval "<js>"` runs JS in the page **and awaits promises** — use an
  async IIFE returning a JSON-serializable value to verify async paths (worker
  disparity parity, orbit angle) headlessly, without adding to the app's selftest.
  Navigate to plain `index.html` (not `?selftest`) first so the app fns are in scope.
- Headless Edge exposes no motion sensor: drive the IMU/orbit path by dispatching
  `new Event('deviceorientationabsolute')` with an expando `.alpha` — `readHeading`
  reads `.alpha`/`.webkitCompassHeading` as plain property reads, so it works.
  Note: the returned angle can wrap opposite to a naive `normAngle(heading−ref)`
  reading (zeroed at 123.4°, then dispatching 200° gave angle 283.4°) — check
  the sign convention before trusting QA numbers.
- Headless capture note: `takePhoto` yields no blobs when the video never plays
  (autoplay blocked → `videoWidth` 0, silent 0×0 capture) even with streams set;
  verify camera-pipeline work via the frame path (upload/`setFrame` → Compute
  Depth → export) instead, and verify downloads by stashing
  `URL.createObjectURL` blobs inside eval (inspect header/size, e.g. PLY =
  `ply\nformat`).
- Run exactly **one `agent-browser` command per bash invocation** (a chained
  connect+open+wait+get-title call hung >90 s; separate calls are instant).
  `get title` reads selftest results headlessly (e.g. `SELFTEST 28/28` over
  file://, opened as `file:///C:/…/index.html?selftest`); `close` also
  terminates the attached Edge and frees its port.
- `agent-browser click` can fail with "covered by <video#v…>" on this app at
  narrow viewports: `main` is an inner scroll container the tool doesn't scroll
  into its hit-test coords. Normalize first (`eval "document.querySelector(
  'main').scrollTop=0"` or `scrollintoview`), then click; or drive handlers via
  `eval` (`button.click()`). App layout itself shows no overlap at scroll 0.
- `agent-browser connect <port>` may print "launched browser" and silently
  control its own Chromium instead of your Edge (after Edge restarts or
  `close --all`). Verify with `get url` (about:blank = wrong browser) before
  camera tests; a long-lived Edge instance also stops reporting the fake
  device — reboot Edge, or override `getUserMedia` in-page (canvas
  `captureStream()`) for deterministic capture tests.

## Skills
- Custom skills live in `C:\Users\HP\.agents\skills\`. `html-to-android-pwa`
  captures the PWA-finalization workflow with a dependency-free Node+zlib icon
  generator and manifest/sw templates; the icons were generated from it.