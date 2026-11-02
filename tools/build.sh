#!/usr/bin/env bash
# Buduje APK na Questa i (opcjonalnie) instaluje/uruchamia przez adb.
#   tools/build.sh            debug APK -> build/asteroids-vr.apk
#   tools/build.sh run        + instalacja i start na goglach
#   tools/build.sh log        logcat gry
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-$HOME/opt/android-sdk}"
ADB="$SDK/platform-tools/adb"
PKG=com.asteroidsvr.game
APK=build/asteroids-vr.apk

if [[ "${1:-}" == log ]]; then exec "$ADB" logcat -s godot; fi

mkdir -p build
args=(--headless --path . --export-debug Quest "$APK")
[[ -d android/build ]] || args=(--install-android-build-template "${args[@]}")
godot "${args[@]}"
[[ -f "$APK" ]] || { echo "Brak $APK — eksport się nie udał"; exit 1; }
echo "OK: $APK ($(du -h "$APK" | cut -f1))"

if [[ "${1:-}" == run ]]; then
	"$ADB" install -r "$APK"
	"$ADB" shell am force-stop "$PKG" || true
	act=$("$ADB" shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')
	"$ADB" shell am start -n "$act"
	echo "Uruchomiono $PKG na goglach. Logi: tools/build.sh log"
fi
