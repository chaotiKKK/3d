// FreeCam3D desktop shell (Electron).
// Serves the single-file PWA over loopback HTTP so the app keeps its secure
// context (service worker, camera) — file:// would drop both — and opens it
// in a plain BrowserWindow. The web app itself is untouched: no preload,
// nodeIntegration off, sandbox on.
//
//   npm start                -> run from source (serves ./app)
//   FreeCam3D.exe --selfcheck -> hidden window, runs ?selftest, prints
//                                PASS/FAIL to stdout, exits 0/1 (for CI/QA)

const { app, BrowserWindow, session } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');

const SELFCHECK = process.argv.includes('--selfcheck');
// When packaged, __dirname is inside app.asar; fs reads through asar fine.
const WEB = path.join(__dirname, 'app');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

function createServer() {
  return http.createServer((req, res) => {
    let p;
    try { p = decodeURIComponent((req.url || '/').split('?')[0]); }
    catch (e) { p = '/'; }
    if (p === '/') p = '/index.html';
    const file = path.join(WEB, p);
    const rel = path.relative(WEB, file);
    if (rel.startsWith('..') || path.isAbsolute(rel)) {
      res.writeHead(403); res.end('forbidden'); return;
    }
    fs.readFile(file, (err, buf) => {
      if (err) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'Cache-Control': 'no-store' // the app's own SW does the caching
      });
      res.end(buf);
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function grantMedia(ses) {
  // Camera/mic permission: getUserMedia + enumerateDevices need both handlers.
  ses.setPermissionCheckHandler((_wc, permission) => permission === 'media');
  ses.setPermissionRequestHandler((_wc, permission, callback) =>
    callback(permission === 'media'));
  // Captures download as files (no save dialog per burst) into ~/Downloads.
  ses.on('will-download', (_e, item) => {
    const dir = app.getPath('downloads');
    item.setSavePath(path.join(dir, item.getFilename()));
  });
}

async function runSelfcheck(win, url) {
  // Cold first run can lose the SW race (selftest's 4 s caps): give the SW a
  // second attempt after it has had time to activate.
  let finalTitle = '';
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      await win.loadURL(url + '&again=' + attempt + '&v=' + Date.now());
    } catch (e) {
      console.error('[selfcheck] load failed: ' + e.message);
      break;
    }
    const t0 = Date.now();
    while (Date.now() - t0 < 30000) {
      await sleep(300);
      let title = '';
      try { title = await win.webContents.executeJavaScript('document.title'); } catch (e) { /* page mid-load */ }
      const m = /^SELFTEST (\d+)\/(\d+)/.exec(title || '');
      if (m) {
        finalTitle = title;
        if (m[1] === m[2]) {
          console.log('[selfcheck] PASS ' + title);
          app.exit(0);
          return;
        }
        console.log('[selfcheck] attempt ' + attempt + ' partial: ' + title + ' — retrying after SW warm-up');
        break; // wait for the next attempt
      }
    }
    await sleep(5000); // let the SW finish activating before reloading
  }
  console.error('[selfcheck] FAIL final title=' + (finalTitle || '(none)'));
  app.exit(1);
}

if (!SELFCHECK && !app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.whenReady().then(() => {
    grantMedia(session.defaultSession);
    const server = createServer();
    server.listen(0, '127.0.0.1', () => {
      const url = 'http://127.0.0.1:' + server.address().port + '/';
      const win = new BrowserWindow({
        width: 1280,
        height: 860,
        show: !SELFCHECK,
        title: 'FreeCam3D',
        backgroundColor: '#0a0c14',
        webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
      });
      win.on('closed', () => server.close());
      if (SELFCHECK) runSelfcheck(win, url + '?selftest');
      else win.loadURL(url);
    });
  });
}

app.on('window-all-closed', () => app.quit());
