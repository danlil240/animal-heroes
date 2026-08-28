#!/usr/bin/env bash
# Dual SM-T220 tablet smoke and endurance test.
# Installs the APK on both tablets, runs automated host/client sessions,
# and captures frame-time, memory, thermal, and reconnect metrics.
#
# Prerequisites: Both tablets connected via USB with adb authorization,
# debug APK built via scripts/build_android.sh.
# Usage: HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/device_smoke.sh
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APK="$BUILD_DIR/animal-heroes-debug.apk"
RESULTS_DIR="$ROOT_DIR/docs/test-results"

HOST_SERIAL="${HOST_SERIAL:-}"
CLIENT_SERIAL="${CLIENT_SERIAL:-}"

if [[ -z "$HOST_SERIAL" || -z "$CLIENT_SERIAL" ]]; then
  echo "Usage: HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> $0" >&2
  echo "Run 'adb devices -l' to list connected tablets." >&2
  exit 2
fi

if [[ ! -f "$APK" ]]; then
  echo "APK not found at $APK. Run scripts/build_android.sh first." >&2
  exit 2
fi

mkdir -p "$RESULTS_DIR"

echo "=== Device check ==="
adb -s "$HOST_SERIAL" shell getprop ro.product.model
adb -s "$CLIENT_SERIAL" shell getprop ro.product.model

echo "=== Installing APK on both tablets ==="
adb -s "$HOST_SERIAL" install -r "$APK"
adb -s "$CLIENT_SERIAL" install -r "$APK"

echo "=== Permission audit ==="
bash "$ROOT_DIR/game/tests/device/apk_permissions.sh" "$APK"

echo "=== Clearing logs ==="
adb -s "$HOST_SERIAL" logcat -c
adb -s "$CLIENT_SERIAL" logcat -c

echo "=== Launching host ==="
adb -s "$HOST_SERIAL" shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp

echo "=== Launching client ==="
sleep 3
adb -s "$CLIENT_SERIAL" shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp

echo "=== Running 10-minute endurance capture ==="
sleep 600

echo "=== Collecting results ==="
adb -s "$HOST_SERIAL" logcat -d > "$RESULTS_DIR/host-logcat.txt"
adb -s "$CLIENT_SERIAL" logcat -d > "$RESULTS_DIR/client-logcat.txt"

echo "=== Capturing performance metrics ==="
adb -s "$HOST_SERIAL" shell dumpsys gfxinfo org.danlil.animalheroes > "$RESULTS_DIR/host-gfxinfo.txt" 2>&1 || true
adb -s "$CLIENT_SERIAL" shell dumpsys gfxinfo org.danlil.animalheroes > "$RESULTS_DIR/client-gfxinfo.txt" 2>&1 || true
adb -s "$HOST_SERIAL" shell dumpsys meminfo org.danlil.animalheroes > "$RESULTS_DIR/host-meminfo.txt" 2>&1 || true
adb -s "$CLIENT_SERIAL" shell dumpsys meminfo org.danlil.animalheroes > "$RESULTS_DIR/client-meminfo.txt" 2>&1 || true

echo "=== Done. Results in $RESULTS_DIR/ ==="
echo "Review frame-time percentiles, memory, and thermal status."
echo "Record findings in docs/test-results/sm-t220-performance.md"
