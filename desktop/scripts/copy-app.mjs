// Copies the deployable web shell from the project root into ./app so the
// packaged EXE is self-contained (runs without the source tree next to it).
import { mkdirSync, copyFileSync, rmSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..'); // project root
const appDir = path.resolve(here, '..', 'app');

const FILES = [
  'index.html',
  'sw.js',
  'manifest.webmanifest',
  'icon-192.png',
  'icon-512.png'
];

rmSync(appDir, { recursive: true, force: true });
mkdirSync(appDir, { recursive: true });
let n = 0;
for (const f of FILES) {
  const src = path.join(root, f);
  if (!existsSync(src)) throw new Error('missing source file: ' + src);
  copyFileSync(src, path.join(appDir, f));
  n++;
}
console.log('copy-app: ' + n + ' files -> ' + appDir);
