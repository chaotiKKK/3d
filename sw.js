/* Cache-first service worker for FreeCam3D (single-file static PWA shell).
 * Bump CACHE (…-v1 → -v2 → …) on every release so the activate handler evicts
 * the old cache and users get fresh files instead of a permanently stale shell.
 * External CDN assets (Google Fonts) are NOT precached — they are cached at
 * runtime on first fetch, so one CDN failure can't break the install. */
const CACHE = 'freecam3d-v3';
const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (e) => {
  // Best-effort precache: don't let one missing optional file fail the install.
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      Promise.allSettled(SHELL.map((u) => c.add(u)))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                 // never cache mutations
  e.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;                          // cache-first for the shell
      return fetch(req).then((res) => {
        // Runtime-cache successful same-origin/CDN GETs for next offline launch.
        // Only http(s) URLs: caches.put() rejects other schemes (chrome-extension:,
        // data:, …) with a TypeError. Cache writes are best-effort, so failures
        // must never surface to the page as unhandled rejections.
        if (res && res.status === 200 && (res.type === 'basic' || res.type === 'cors') &&
            /^https?:$/.test(new URL(req.url).protocol)) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => caches.match('./index.html')); // offline navigation fallback
    })
  );
});