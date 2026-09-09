# Playwright UI smoke for FreeCam3D — runs against a live server (python -m http.server 8080).
# Covers: ?selftest verdict (cross-check of .build/ci-selftest.mjs), fresh-profile
# onboarding, scan-recipe snapping, the photo pipeline over a FAKE camera
# (canvas.captureStream()-backed getUserMedia → Photo → ZIP download), and
# console/pageerror cleanliness.
# Run: .build/pw-venv/Scripts/python.exe .build/ui-smoke.py
from playwright.sync_api import sync_playwright
import time

BASE = 'http://localhost:8080'
SHOTS = '.build/ui-shots'
failures = []


def check(name, cond):
    print(f'  [{"PASS" if cond else "FAIL"}] {name}')
    if not cond:
        failures.append(name)


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)

    # --- 1) Selftest verdict, independently of the CDP harness -----------------
    ctx = browser.new_context()
    page = ctx.new_page()
    page_errors, logs = [], []
    page.on('pageerror', lambda e: page_errors.append(str(e)))
    page.on('console', lambda m: logs.append(m.text))
    page.goto(f'{BASE}/?selftest&v=pw-{int(time.time())}', wait_until='networkidle')
    page.wait_for_function("document.title.startsWith('SELFTEST ')", timeout=30000)
    title = page.title()
    check('selftest title is 69/69', title == 'SELFTEST 69/69')
    check('selftest console ALL PASS', any('ALL PASS 69/69' in l for l in logs))
    page.screenshot(path=f'{SHOTS}/selftest.png', full_page=True)
    ctx.close()

    # --- 2) Fresh profile: onboarding + recipes ---------------------------------
    ctx = browser.new_context()
    page = ctx.new_page()
    page_errors2, logs2 = [], []
    page.on('pageerror', lambda e: page_errors2.append(str(e)))
    page.on('console', lambda m: logs2.append(m.text))
    page.goto(f'{BASE}/', wait_until='networkidle')

    onboard = page.locator('#onboard')
    check('onboarding banner visible on first run', onboard.is_visible())
    check('onboarding shows Schritt 1/3', '1/3' in page.locator('#onboardStepN').inner_text())
    page.screenshot(path=f'{SHOTS}/onboarding.png', full_page=True)

    page.click('button.rec-tab[data-recipe="person"]')
    check('person tab active', page.locator('button.rec-tab[data-recipe="person"]').evaluate(
        'el => el.classList.contains("on")'))
    check('person snaps count=90', page.input_value('#numTot') == '90')
    check('person snaps interval=2', page.input_value('#numInt') == '2')
    check('person snaps res=1920x1080', page.input_value('#selRes') == '1920x1080')
    check('person spec line says 90 F', '90 F' in page.locator('#recSpec').inner_text())

    page.click('button.rec-tab[data-recipe="objekt"]')
    check('objekt snaps TT frames=48', page.input_value('#numTT') == '48')
    check('objekt snaps TT angle=7.5', page.input_value('#numTA') == '7.5')
    check('objekt snaps TT settle=1', page.input_value('#numTS') == '1')
    check('objekt spec line has 7,5°', '7,5°' in page.locator('#recSpec').inner_text())
    page.screenshot(path=f'{SHOTS}/recipes.png', full_page=True)

    check('no page errors (selftest walk)', not page_errors)
    check('no page errors (UI walk)', not page_errors2)
    ctx.close()

    # --- 3) Photo pipeline over Chromium's FAKE camera ---------------------------
    # A separate browser instance launched with --use-fake-device-for-media-stream
    # (Chromium's built-in green-ball test camera): the app takes its REAL path —
    # device enumeration fills the slot select, getUserMedia returns frames, the
    # Photo button captures via ImageCapture/canvas — and the downloader shim
    # captures the ZIP/image blob so nothing touches disk. (Overriding getUserMedia
    # with a canvas.captureStream was tried first and is weaker: a fresh context
    # enumerates zero devices, so the slot select stays empty and Start skips it.)
    fb = p.chromium.launch(headless=True, args=[
        '--use-fake-device-for-media-stream',
        '--use-fake-ui-for-media-stream',
    ])
    ctx = fb.new_context(permissions=['camera'])
    page = ctx.new_page()
    page_errors3, logs3 = [], []
    page.on('pageerror', lambda e: page_errors3.append(str(e)))
    page.on('console', lambda m: logs3.append(m.text))
    page.goto(f'{BASE}/', wait_until='networkidle')

    check('fake camera enumerated in slot 0', page.evaluate(
        '''() => Array.from(document.querySelector('#selDev0').options).some(o => o.value !== '')'''))
    page.click('button:has-text("Start")')
    page.wait_for_timeout(1500)
    # Chromium's single fake device fills ALL THREE slots (the app opens one
    # stream per configured slot; vidW>0 proves live frames flow).
    check('fake cameras started (camN=3)', page.locator('#camN').inner_text() == '3')
    check('fake stream has frames (videoWidth>0)', page.evaluate("() => vids[0] && vids[0].videoWidth > 0"))

    # Shim the downloader BEFORE Photo: capture {name, size, type} instead of writing a file.
    page.evaluate('''() => {
      window.__dl = [];
      window.downloadBlob = (blob, fn) => {
        window.__dl.push({ fn, size: blob.size, type: blob.type });
      };
    }''')
    page.click('button:has-text("Photo")')
    page.wait_for_timeout(2000)
    dl = page.evaluate('() => window.__dl')
    check('Photo produced one download', len(dl) == 1)
    if dl:
        name, size, typ = dl[0]['fn'], dl[0]['size'], dl[0]['type']
        check('photo is a single Photo-ZIP', name.startswith('freecam3d_photo_') and typ == 'application/zip')
        check('ZIP is non-trivial (3 shots packed)', size > 5000)
    check('shot counter incremented to 3', page.locator('#shotN').inner_text() == '3')
    # log()/toast() write into DOM state, not console — assert against the UI:
    check('cam 0 active log entry', 'Cam 0 active' in page.locator('#logD').inner_text())
    check('photo saved toast', 'Foto(s) gespeichert' in page.evaluate("() => document.body.innerText"))
    check('no page errors (photo walk)', not page_errors3)
    page.screenshot(path=f'{SHOTS}/photo-fake-cam.png', full_page=True)
    ctx.close()
    fb.close()
    browser.close()

print(f'\nUI SMOKE {"PASS" if not failures else "FAIL"} — {len(failures)} failure(s)')
raise SystemExit(1 if failures else 0)