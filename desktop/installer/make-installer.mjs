// Builds the NSIS installer from a packaged Electron dist.
//
// Usage: node installer/make-installer.mjs [--version vX.Y.Z[-pre]]
// CI passes the release tag; locally it defaults to desktop/package.json.
// Refuses to run without `npm run pack` output and without makensis
// ($NSIS_EXE, the standard install paths, or `where makensis`).
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url))); // desktop/

const ai = process.argv.indexOf('--version');
const argVer = ai !== -1 && process.argv[ai + 1] ? process.argv[ai + 1] : null;
const full = (argVer || require(path.join(root, 'package.json')).version).replace(/^v/, '');
const numeric = full.match(/^(\d+\.\d+\.\d+)/); // NSIS version resources need X.Y.Z
if (!numeric) {
  console.error(`::error::version '${full}' is not X.Y.Z[...]`);
  process.exit(1);
}

const pkgDir = path.join(root, 'dist', 'FreeCam3D-win32-x64');
if (!existsSync(path.join(pkgDir, 'FreeCam3D.exe'))) {
  console.error('::error::packaged app not found — run `npm run pack` first');
  process.exit(1);
}

function findMakensis() {
  const cands = [
    process.env.NSIS_EXE,
    'C:\\Program Files (x86)\\NSIS\\makensis.exe',
    'C:\\Program Files\\NSIS\\makensis.exe',
  ].filter(Boolean);
  for (const c of cands) if (existsSync(c)) return c;
  const w = spawnSync('where', ['makensis'], { encoding: 'utf8' });
  if (w.status === 0 && w.stdout.trim()) return w.stdout.trim().split(/\r?\n/)[0];
  return null;
}
const makensis = findMakensis();
if (!makensis) {
  console.error('::error::makensis not found — install NSIS (choco install nsis -y) or set NSIS_EXE');
  process.exit(1);
}

// EstimatedSize (KB) for the Add/Remove Programs entry: walk the payload once.
let bytes = 0;
const walk = (d) => {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else bytes += statSync(p).size;
  }
};
walk(pkgDir);
const estKB = Math.max(1, Math.round(bytes / 1024));

const outFile = path.join(root, 'dist', `FreeCam3D-Setup-v${full}.exe`);
console.log(`installer: makensis ${makensis}`);
console.log(`  payload ${pkgDir} (${(bytes / 1048576).toFixed(1)} MB, EstimatedSize ${estKB} KB)`);
console.log(`  out     ${outFile}`);

execFileSync(makensis, [
  `-DVERSION=${numeric[1]}`,
  `-DFULLVERSION=${full}`,
  `-DESTSIZE=${estKB}`,
  `-DPKGDIR=${pkgDir}`,
  `-DOUTFILE=${outFile}`,
  path.join(root, 'installer', 'installer.nsi'),
], { stdio: 'inherit' });

if (!existsSync(outFile)) {
  console.error('::error::makensis reported success but the installer is missing');
  process.exit(1);
}
console.log(`installer OK: ${outFile} (${(statSync(outFile).size / 1048576).toFixed(1)} MB)`);
