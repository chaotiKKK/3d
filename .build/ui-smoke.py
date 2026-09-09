# Playwright UI smoke for FreeCam3D — runs against a live server (python -m http.server 8080).
# Covers: ?selftest verdict (cross-check of .build/ci-selftest.mjs), fresh-profile
# onboarding, scan-recipe snapping, and console/pageerror cleanliness.
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
    browser.close()

print(f'\nUI SMOKE {"PASS" if not failures else "FAIL"} — {len(failures)} failure(s)')
raise SystemExit(1 if failures else 0)