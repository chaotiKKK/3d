#!/usr/bin/env bash
# On-emulator verification for the FreeCam3D APK shell — the CI counterpart of
# the manual AVD recipe in AGENTS.md. Boots nothing itself: expects a booted
# device/emulator with the app installed (the CI job wires that up) OR the
# developer's running AVD (local use). Runs four checks via cdp-verify.mjs:
#   1. WebView serves the app at the appassets origin in a SECURE CONTEXT
#   2. getUserMedia yields real frames (camera permission bridge)
#   3. patched downloadBlob writes exact bytes into /sdcard/Download (MediaStore)
#   4. in-APK selftest reads 67/69 with ONLY the two pwa: checks failing
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

fail() { echo "EMULATOR SMOKE FAIL: $*" >&2; exit 1; }
export PATH="$(cd ../.. >/dev/null 2>&1 && pwd)/.build/apk/android-sdk/platform-tools:$PATH"
command -v adb >/dev/null || fail "adb not on PATH (install platform-tools)"
adb get-state >/dev/null 2>&1 || fail "no android device/emulator attached (adb devices)"

# --- resolve the app's DevTools socket (pid changes per launch) --------------
# NOTE: pidof/grep exit 1 on no-match; with `set -euo pipefail` an unguarded
# assignment dies silently before the fail() below can speak (observed on CI
# where the app was installed but never launched). Every probing assignment
# gets `|| true`; the explicit guards do the reporting.
PID="$(adb shell pidof com.freecam3d.app 2>/dev/null | tr -d '\r' | head -1 || true)"
if [ -z "$PID" ]; then
  echo "== app not running, launching =="
  for i in 1 2 3; do
    adb shell am start -W -n com.freecam3d.app/.MainActivity | grep -q "Status: ok" || { sleep 5; continue; }
    sleep 8
    PID="$(adb shell pidof com.freecam3d.app 2>/dev/null | tr -d '\r' | head -1 || true)"
    [ -n "$PID" ] && break
    sleep 5
  done
  [ -n "$PID" ] || fail "app process did not start (see adb logcat for the crash)"
fi
SOCK="$(adb shell cat /proc/net/unix 2>/dev/null | grep -oE "webview_devtools_remote_[0-9]+" | head -1 || true)"
[ -n "$SOCK" ] || fail "no webview_devtools_remote socket (WebView debugging disabled?)"
adb forward tcp:9222 "localabstract:$SOCK" >/dev/null
sleep 2
node cdp-verify.mjs "return 'cdp-up'" | grep -q cdp-up || fail "CDP not reachable over adb forward"

echo "== check 1: secure-context appassets origin =="
node cdp-verify.mjs "return {href: location.href.startsWith('https://appassets.androidplatform.net/assets/'), secure: window.isSecureContext, patched: !!window.__fcPatched}" \
  | grep -q '"secure": true' || fail "appassets secure context broken"

echo "== check 2: camera bridge (getUserMedia) =="
CAMJSON="$(node cdp-verify.mjs "
const v=document.createElement('video');v.muted=true;v.playsInline=true;
const st=await navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'}});
v.srcObject=st;await v.play();await new Promise(r=>setTimeout(r,2000));
const out={w:v.videoWidth,h:v.videoHeight};
st.getTracks().forEach(t=>t.stop());v.remove();return out" || true)"
echo "$CAMJSON" | grep -q '"w": 480\|"w": 640\|"w": 320\|"w": 1280\|"w": 1920' || fail "getUserMedia gave no frames: $CAMJSON"
echo "  camera: $CAMJSON"

echo "== check 3: MediaStore export via downloadBlob =="
node cdp-verify.mjs "
const data='ply\nfc3d-emulator-smoke\n';const blob=new Blob([data],{type:'application/octet-stream'});
downloadBlob(blob,'fc3d_emu_smoke.ply');await new Promise(r=>setTimeout(r,2500));return 1" | grep -q 1 \
  || fail "downloadBlob bridge did not respond"
adb shell "cat /sdcard/Download/fc3d_emu_smoke.ply" 2>/dev/null | grep -q "fc3d-emulator-smoke" \
  || fail "export file missing/wrong bytes in /sdcard/Download"
adb shell "rm -f /sdcard/Download/fc3d_emu_smoke.ply" >/dev/null
echo "  export: /sdcard/Download round-trip OK (cleaned up)"

echo "== check 4: in-APK selftest 67/69 (only pwa: checks fail) =="
node cdp-verify.mjs "location.href=location.pathname+'?selftest';return 1" >/dev/null
sleep 16
TITLE="$(node cdp-verify.mjs "return document.title")"
echo "$TITLE" | grep -q "SELFTEST 67/69" || fail "selftest title: $TITLE (want SELFTEST 67/69)"
PWA_FAILS="$(adb logcat -d 2>/dev/null | grep -oE '\[selftest\] FAIL: .*' | tail -1 || true)"
echo "$PWA_FAILS" | grep -q "pwa:sw-registered, pwa:cache-primed" || fail "unexpected failing checks: $PWA_FAILS"
echo "  selftest: $TITLE, failures exactly: pwa:sw-registered, pwa:cache-primed"

echo "EMULATOR SMOKE PASS — secure context, camera bridge, MediaStore export, selftest 67/69"
