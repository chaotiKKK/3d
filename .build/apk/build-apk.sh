#!/usr/bin/env bash
# Hand-built APK pipeline for the FreeCam3D WebView shell — no gradle, no global installs.
# Toolchain is project-local: .build/apk/{jdk,android-sdk,webkit}. Output: <repo root>/FreeCam3D.apk
# CI mode: without .build/apk/jdk/ the script falls back to JAVA_HOME (setup-java),
# and the SDK components must already be installed (runner image / sdkmanager).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL_JDK="$ROOT/jdk/jdk-17.0.20.1+1"
if [ -d "$LOCAL_JDK" ]; then
  JDK="$LOCAL_JDK"
else
  JDK="${JAVA_HOME:?set JAVA_HOME to a JDK 17, or provide .build/apk/jdk/}"
fi
SDK="$ROOT/android-sdk"
# CI mode: fall back to the runner's ANDROID_HOME (GitHub's ubuntu image ships
# build-tools 34.0.0 + platforms android-34); fail loudly if neither exists.
if [ ! -d "$SDK/build-tools/34.0.0" ] && [ -n "${ANDROID_HOME:-}" ]; then
  SDK="$ANDROID_HOME"
fi
[ -d "$SDK/build-tools/34.0.0" ] || { echo "ERROR: build-tools 34.0.0 not found (looked in $SDK and \$ANDROID_HOME)" >&2; exit 1; }
BT="$SDK/build-tools/34.0.0"
PLAT="$SDK/platforms/android-34/android.jar"
export JAVA_HOME="$JDK"
export PATH="$JDK/bin:$BT:$PATH"
cd "$ROOT"

# Self-contained deps: pinned AndroidX artifacts (Google Maven), fetched only if absent.
# webkit's WebViewAssetLoader needs androidx.core.util.Pair at RUNTIME (observed:
# ClassNotFoundException on device launch) — dex only the core/util classes to stay
# clear of androidx.core's kotlin cascade.
if [ ! -f webkit/webkit-classes.jar ] || [ ! -f webkit/annotation.jar ] || [ ! -f webkit/core-util.jar ]; then
  echo "== fetch androidx deps =="
  mkdir -p webkit
  curl -fsSL --retry 2 -o webkit/webkit.aar "https://dl.google.com/android/maven2/androidx/webkit/webkit/1.10.0/webkit-1.10.0.aar"
  curl -fsSL --retry 2 -o webkit/annotation.jar "https://dl.google.com/android/maven2/androidx/annotation/annotation/1.7.1/annotation-1.7.1.jar"
  curl -fsSL --retry 2 -o webkit/core.aar "https://dl.google.com/android/maven2/androidx/core/core/1.9.0/core-1.9.0.aar"
  unzip -o -j -q webkit/webkit.aar classes.jar -d webkit/
  mv webkit/classes.jar webkit/webkit-classes.jar
  unzip -o -q webkit/core.aar classes.jar -d webkit/core-classes/
  rm -rf webkit/core-util && mkdir -p webkit/core-util
  (cd webkit/core-classes && "${JDK}/bin/jar" xf classes.jar androidx/core/util)
  (cd webkit/core-classes && "${JDK}/bin/jar" cf ../core-util.jar androidx)
fi

# Single source of truth: embed the repo-root webapp fresh on every build.
mkdir -p app/assets
cp "$ROOT/../../index.html" "$ROOT/../../manifest.webmanifest" "$ROOT/../../sw.js" \
   "$ROOT/../../icon-192.png" "$ROOT/../../icon-512.png" app/assets/

cp "$ROOT/../../icon-192.png" app/res/mipmap-xhdpi/ic_launcher.png
cp "$ROOT/../../icon-512.png" app/res/mipmap-xxxhdpi/ic_launcher.png

rm -rf build && mkdir -p build/gen build/classes build/dex

echo "== aapt2 compile res =="
"$BT/aapt2" compile --dir app/res -o build/res.zip

echo "== aapt2 link (manifest + res + assets) =="
"$BT/aapt2" link -o build/base.apk -I "$PLAT" \
  --manifest app/AndroidManifest.xml -R build/res.zip -A app/assets \
  --java build/gen --auto-add-overlay

echo "== javac =="
javac -source 8 -target 8 -Xlint:-options -nowarn \
  -bootclasspath "$PLAT" \
  -classpath "$ROOT/webkit/webkit-classes.jar:$ROOT/webkit/annotation.jar" \
  -d build/classes \
  build/gen/com/freecam3d/app/R.java app/java/com/freecam3d/app/MainActivity.java

echo "== d8 (dex app + webkit + annotation + core-util) =="
D8="$BT/d8.bat"; [ -f "$D8" ] || D8="$BT/d8"
"$D8" --release --lib "$PLAT" --min-api 24 --output build/dex \
  $(find build/classes -name '*.class') "$ROOT/webkit/webkit-classes.jar" "$ROOT/webkit/annotation.jar" "$ROOT/webkit/core-util.jar"

echo "== package =="
cp build/base.apk build/unsigned.apk
(cd build/dex && aapt add ../unsigned.apk classes.dex)

echo "== zipalign =="
"$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk

if [ ! -f debug.keystore ]; then
  echo "== keystore =="
  keytool -genkeypair -keystore debug.keystore -alias freecam -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android -dname "CN=FreeCam3D"
fi

echo "== apksigner =="
SIGNER="$BT/apksigner.bat"; [ -f "$SIGNER" ] || SIGNER="$BT/apksigner"
"$SIGNER" sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --out "$ROOT/../../FreeCam3D.apk" build/aligned.apk

echo "OK -> $(cd "$ROOT/../.." && pwd)/FreeCam3D.apk"
