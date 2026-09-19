# FreeCam3D — Stereo 3D Scanner (PWA)

Einzeldatei-PWA: Webcams/Smartphone-Kamera(s) → Foto-Sequenzen → Stereo-Disparität →
Tiefenkarte → Punktwolke (PLY/OBJ) — alles im Browser, installierbar & offlinefähig.

## Dateien

| Datei | Zweck |
|---|---|
| `index.html` | Die komplette App (UI + Logik, keine Abhängigkeiten) |
| `manifest.webmanifest` | Web-App-Manifest (Installation) |
| `sw.js` | Cache-first Service Worker (Offline-Start) |
| `icon-192.png`, `icon-512.png` | Icons (auch maskable) |

## Hosting & Installation (Android)
1. **Dateien über HTTPS hosten** — jede statische Hosting-Plattform (GitHub Pages,
   Netlify, Vercel, Cloudflare Pages) reicht; einfach diesen Ordner hochladen.
   Wichtig: **HTTPS ist Pflicht** — Kamera-Zugriff, Service Worker und der
   Install-Button funktionieren nicht über `file://`. Für Tests reicht der
   lokale Rechner: `python -m http.server 8080` / `npx http-server -p 8080 .`,
   dann im Browser `http://localhost:8080` öffnen (localhost gilt als sicher).
2. **Installieren:** in Chrome (Android) das ⋮-Menü → *App installieren* /
   *Zum Startbildschirm hinzufügen*. Die App startet dann ohne Browserleiste und
   auch offline (Shell wird vom Service Worker gecacht; neue Versionen kommen
   durch Cache-Namen-Bump `freecam3d-v1 → v2 in sw.js`).
3. **Stale Cache beim Entwickeln:** Der Service Worker ist cache-first — nach
   Code-Änderungen kann eine alte Version hängen bleiben. Neue Inhalte kommen
   erst, wenn der `CACHE`-Name in `sw.js` hochgezählt wurde („Bump on every
   release“); der neue SW evicted beim Aktivieren die alten Caches. Beim lokalen
   Testen zusätzlich in den DevTools unter *Application → Service Workers*
   „Update on reload“ aktivieren oder einmal „Unregister“ + „Clear site data“
   ausführen — ein harter Reload (`Ctrl+Shift+R`) genügt **nicht**, weil der
   Service Worker selbst aus dem Cache antwortet.

## Installation (Windows)

- **Installer:** Auf der [GitHub-Releases-Seite](https://github.com/chaotiKKK/3d/releases)
  die `FreeCam3D-Setup-vX.Y.Z.exe` herunterladen und starten. Per-user-Install
  nach `%LOCALAPPDATA%\Programs\FreeCam3D` — **kein Administrator** nötig;
  Startmenü- und Desktop-Verknüpfung werden angelegt, Deinstallation über
  Windows-Einstellungen → Apps. Der Installer ist Authenticode-signiert
  (Timestamp via DigiCert); das Zertifikat ist derzeit **selbstsigniert**, d. h.
  Windows zeigt beim ersten Start eine SmartScreen-Warnung („unbekannter
  Herausgeber") — „Weitere Informationen → Trotzdem ausführen“. Stille
  Installation/Deinstallation für Skripte: `FreeCam3D-Setup.exe /S` bzw.
  `uninstall.exe /S`.
- **Portable Nutzung ohne Installation:** das gepackte Verzeichnis
  `desktop/dist/FreeCam3D-win32-x64/` nach `npm run pack` direkt starten —
  die App ist selbst-contained.

## Bedienung

- **Kameras:** Gerät pro Slot wählen → *Start*. Foto/Burst/Intervall/Turntable
  fangen pro Kamera Bilder.
- **Downloads:** Sequenzen (Serienbild/Intervall/Turntable, Videos) werden in
  **einem** ZIP zusammengepackt — Android blockiert viele Einzel-Downloads.
- **Tiefe:** *Compute Depth* braucht zwei Ansichten: entweder 2 Live-Kameras
  (Desktop-Rig) oder **eine** Kamera + zwei verschobene Aufnahmen über
  *Load Frame L / Load Frame R*. Anschließend *3D View*, *Export PLY/OBJ*,
  *Depth PNG*.
- **Projekt sichern:** *Export Project* erzeugt ein ZIP mit `project.json` +
  allen Bildern; *Restore Project* nimmt ZIP (oder altes JSON) wieder entgegen
  und legt die Bilder zurück in den Blob-Speicher (✓ = wieder exportierbar).
  Gespeicherte Blobs liegen in **IndexedDB** (nicht localStorage), gekappt auf
  die 300 neuesten Aufnahmen.

## Eigenheiten / Grenzen (bewusst so gebaut)

- **Eine Kamera auf Android:** Die meisten Android-Geräte können **nicht zwei
  `getUserMedia`-Streams gleichzeitig** öffnen. Auf dem Handy wird deshalb Slot 0
  benutzt; Stereo läuft über zwei nacheinander aufgenommene/geladene Bilder
  (Frame L/R). Das alte WebSocket-Rig (Server-seitige Kameras) wurde entfernt —
  es war tot auf dem Handy.
- **Secure context:** Kamera, Service Worker, Install-Prompt benötigen HTTPS
  oder `localhost`; `file://` reicht nicht.
- **IndexedDB-Daten** gehören zur Origin — Löschen der Website-Daten entfernt
  die gespeicherten Aufnahmen. Wichtiges vorher als Projekt-ZIP exportieren.
- **Kalibrierung:** Ohne Kalibrations-JSON werden Schätzwerte benutzt
  (Baseline 60 mm, f = 1000 px) — Abstände dann nur grob.

## Selbsttest

`http://localhost:8080/?selftest` führt die Logik-Assertions im Browser aus
(u. a. ZIP-Roundtrip, Stereo-Matching, Projekt-Schema, CRC32, Orbit-Winkel,
Onboarding-Regel, Log-Level-Klassifikation, Guard-Texte, Capture-Ton-Lautstärke,
Qualitäts-Triage, scan_meta-Vertrag, Scan-Rezepte) und zeigt ein grünes
`SELFTEST n/n OK`-Banner; zusätzlich werden `document.title` und in der
Konsole `[selftest] ALL PASS n/n` gesetzt.

Zählweise: 66 feste Prüfungen plus ein gated Worker-Paritäts-Check (Disparität
des Blob-Web-Workers gegen den Hauptthread — nur gewertet, wenn der Worker
antwortet) = 67 in jeder Umgebung. Über HTTP kommen zwei weitere
Service-Worker-/Cache-Prüfungen (SW registriert, Cache `freecam3d-*` geprimed)
dazu: **69/69 über HTTP, 67/67 über `file://`** (dort werden die zwei
SW/Cache-Prüfungen stillschweigend übersprungen).