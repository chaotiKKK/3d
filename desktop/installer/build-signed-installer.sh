#!/usr/bin/env bash
# Build + sign the FreeCam3D Windows installer (NSIS, Authenticode).
# One recipe shared by CI (release.yml tag build, selftest.yml desktop QA)
# and local runs, so CI proves exactly the path a developer runs.
#
# Env (all optional):
#   VERSION          version to stamp (default: desktop/package.json version)
#   CODESIGN_PFX     path to a code-signing PFX. Unset => a self-signed
#                    certificate is generated/derived locally (test-quality,
#                    like the APK debug keystore: SmartScreen shows an unknown
#                    publisher; a real CA cert later is a secret swap only).
#   CODESIGN_PASS    PFX password (default 'freecam3d', matches gen-cert.ps1)
#   NSIS_EXE         makensis path; probed from .build/tools/nsis-3.11 and
#                    the standard install dirs when unset
#
# Steps: verify packaged app exists -> sign app exe -> makensis -> sign
# installer -> verify both signatures. Fails loudly on any missing piece.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root (script lives in desktop/installer/)

REPO="$(pwd)"
APP_EXE="desktop/dist/FreeCam3D-win32-x64/FreeCam3D.exe"
# Accept VERSION with or without a leading v (CI passes the tag, package.json
# carries a bare version) and normalize to the bare form everywhere below.
VERSION="${VERSION:-$(node -p "require('./desktop/package.json').version")}"
VERSION="${VERSION#v}"

# --- 0. sanity -------------------------------------------------------------
[ -f "$APP_EXE" ] || { echo "::error::packaged app missing — run: cd desktop && npm run pack"; exit 1; }

# --- 1. locate / create signing material -----------------------------------
PFX="${CODESIGN_PFX:-.build/codesign.pfx}"
PASS="${CODESIGN_PASS:-freecam3d}"
if [ ! -f "$PFX" ]; then
  echo "[installer] no PFX at $PFX — generating self-signed code-signing cert"
  powershell -NoProfile -ExecutionPolicy Bypass \
    -File desktop/installer/gen-cert.ps1 \
    -OutPfx "$(cygpath -w "$PFX")" -Password "$PASS"
fi

# --- 2. locate makensis ----------------------------------------------------
if [ -z "${NSIS_EXE:-}" ]; then
  for c in "$REPO/.build/tools/nsis-3.11/makensis.exe" \
           "/c/Program Files (x86)/NSIS/makensis.exe" \
           "/c/Program Files/NSIS/makensis.exe"; do
    [ -f "$c" ] && { NSIS_EXE="$c"; break; }
  done
  [ -n "${NSIS_EXE:-}" ] || { echo "::error::makensis not found — set NSIS_EXE or install NSIS"; exit 1; }
fi
echo "[installer] makensis: $NSIS_EXE"

# --- 3. sign the app exe BEFORE packing it into the installer --------------
echo "[installer] signing app exe"
powershell -NoProfile -ExecutionPolicy Bypass \
  -File desktop/installer/sign.ps1 \
  -PfxPath "$(cygpath -w "$PFX")" -PfxPassword "$PASS" \
  -TargetExe "$(cygpath -w "$REPO/$APP_EXE")"

# --- 4. build the installer -------------------------------------------------
export NSIS_EXE
echo "[installer] building setup exe (v$VERSION)"
( cd desktop && node installer/make-installer.mjs --version "$VERSION" )

SETUP_EXE="desktop/dist/FreeCam3D-Setup-v$VERSION.exe"
[ -f "$SETUP_EXE" ] || { echo "::error::installer output missing: $SETUP_EXE"; exit 1; }

# --- 5. sign the installer itself -------------------------------------------
echo "[installer] signing setup exe"
powershell -NoProfile -ExecutionPolicy Bypass \
  -File desktop/installer/sign.ps1 \
  -PfxPath "$(cygpath -w "$PFX")" -PfxPassword "$PASS" \
  -TargetExe "$(cygpath -w "$REPO/$SETUP_EXE")"

# --- 6. verify both Authenticode signatures are embedded --------------------
echo "[installer] verifying signatures"
powershell -NoProfile -ExecutionPolicy Bypass \
  -File desktop/installer/verify-signature.ps1 \
  -ExePath "$(cygpath -w "$REPO/$APP_EXE")" \
  -ExePath2 "$(cygpath -w "$REPO/$SETUP_EXE")"

echo "[installer] OK: $SETUP_EXE"
