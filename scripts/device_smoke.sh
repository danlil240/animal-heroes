#!/usr/bin/env bash
# Dual SM-T220 tablet smoke and endurance test.
# Installs the APK on both tablets and captures before/after device evidence.
# The operator performs the in-game host/join and Cloud Factory traversal.
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
APK_CHECKSUM_FILE="$APK.sha256"
RESULTS_DIR="${SMOKE_RESULTS_DIR:-$ROOT_DIR/docs/test-results}"
RELEASE_RESULTS_DIR="$(realpath -m -- "$ROOT_DIR/docs/test-results")"
RESULTS_DIR="$(realpath -m -- "$RESULTS_DIR")"
DEFAULT_SMOKE_DURATION_SECONDS=600
SMOKE_DURATION_SECONDS="${SMOKE_DURATION_SECONDS:-$DEFAULT_SMOKE_DURATION_SECONDS}"

source "$SCRIPT_DIR/android_tools.sh"
resolve_android_tools

HOST_SERIAL="${HOST_SERIAL:-}"
CLIENT_SERIAL="${CLIENT_SERIAL:-}"

if [[ -z "$HOST_SERIAL" || -z "$CLIENT_SERIAL" ]]; then
  echo "Usage: HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> $0" >&2
  echo "Run '$ADB_BIN devices -l' to list connected tablets." >&2
  exit 2
fi

if [[ "$HOST_SERIAL" == "$CLIENT_SERIAL" ]]; then
  echo "HOST_SERIAL and CLIENT_SERIAL must be different devices." >&2
  exit 2
fi

if [[ ! -f "$APK" ]]; then
  echo "APK not found at $APK. Run scripts/build_android.sh first." >&2
  exit 2
fi

if [[ ! -f "$APK_CHECKSUM_FILE" ]]; then
  echo "APK checksum file not found at $APK_CHECKSUM_FILE. Run scripts/build_android.sh first." >&2
  exit 2
fi

if ! [[ "$SMOKE_DURATION_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "SMOKE_DURATION_SECONDS must be a non-negative number of seconds." >&2
  exit 2
fi

if [[ "$SMOKE_DURATION_SECONDS" != "$DEFAULT_SMOKE_DURATION_SECONDS" && "${SMOKE_TEST_MODE:-}" != "1" ]]; then
  echo "Non-default SMOKE_DURATION_SECONDS requires SMOKE_TEST_MODE=1 and is test-only." >&2
  exit 2
fi

if [[ "${SMOKE_TEST_MODE:-}" == "1" && ( "$RESULTS_DIR" == "$RELEASE_RESULTS_DIR" || "$RESULTS_DIR" == "$RELEASE_RESULTS_DIR"/* ) ]]; then
  echo "Test-only SMOKE_DURATION_SECONDS requires SMOKE_RESULTS_DIR outside release evidence." >&2
  exit 2
fi

mkdir -p "$RESULTS_DIR"

if ! sha256sum --check "$APK_CHECKSUM_FILE"; then
  echo "APK checksum verification failed; do not install or record device evidence." >&2
  exit 2
fi
APK_SHA256="$(sha256sum "$APK" | awk '{print $1}')"
printf '%s\n' "$APK_SHA256" > "$RESULTS_DIR/apk-sha256.txt"
printf '%s\n' "$SMOKE_DURATION_SECONDS" > "$RESULTS_DIR/run-duration-seconds.txt"

require_sm_t220() {
  local role="$1"
  local serial="$2"
  local model
  model="$("$ADB_BIN" -s "$serial" shell getprop ro.product.model)"
  if [[ "$model" != "SM-T220" ]]; then
    echo "ERROR: $role device $serial must report exactly SM-T220; got: $model" >&2
    exit 2
  fi
}

capture_snapshot() {
  local role="$1"
  local serial="$2"
  local timing="$3"
  local prefix="$RESULTS_DIR/${role}-${timing}"

  "$ADB_BIN" -s "$serial" shell getprop ro.product.model > "${prefix}-model.txt"
  "$ADB_BIN" -s "$serial" shell dumpsys gfxinfo org.danlil.animalheroes > "${prefix}-gfxinfo.txt"
  "$ADB_BIN" -s "$serial" shell dumpsys meminfo org.danlil.animalheroes > "${prefix}-meminfo.txt"
  "$ADB_BIN" -s "$serial" shell dumpsys thermalservice > "${prefix}-thermalservice.txt"
  "$ADB_BIN" -s "$serial" shell dumpsys battery > "${prefix}-battery.txt"
  "$ADB_BIN" -s "$serial" logcat -d > "${prefix}-logcat.txt"
}

echo "=== Device check ==="
require_sm_t220 "host" "$HOST_SERIAL"
require_sm_t220 "client" "$CLIENT_SERIAL"

echo "=== Installing checksum-verified APK on both tablets ==="
"$ADB_BIN" -s "$HOST_SERIAL" install -r "$APK"
"$ADB_BIN" -s "$CLIENT_SERIAL" install -r "$APK"

echo "=== Permission audit ==="
bash "$ROOT_DIR/game/tests/device/apk_permissions.sh" "$APK"

echo "=== Clearing logs ==="
"$ADB_BIN" -s "$HOST_SERIAL" logcat -c
"$ADB_BIN" -s "$CLIENT_SERIAL" logcat -c

echo "=== Capturing before-run device evidence ==="
capture_snapshot "host" "$HOST_SERIAL" "before"
capture_snapshot "client" "$CLIENT_SERIAL" "before"

echo "=== Launching host ==="
"$ADB_BIN" -s "$HOST_SERIAL" shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp

echo "=== Launching client ==="
sleep 3
"$ADB_BIN" -s "$CLIENT_SERIAL" shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp

if [[ "$SMOKE_DURATION_SECONDS" == "$DEFAULT_SMOKE_DURATION_SECONDS" ]]; then
  echo "=== Operator-driven 10-minute gameplay interval (600 seconds) ==="
else
  echo "=== TEST ONLY: operator-driven ${SMOKE_DURATION_SECONDS}-second gameplay interval ==="
fi
echo "On both tablets, host/join the game and traverse Cloud Factory during this interval."
echo "Launching the app processes does not automatically perform gameplay."
sleep "$SMOKE_DURATION_SECONDS"

echo "=== Capturing after-run device evidence ==="
capture_snapshot "host" "$HOST_SERIAL" "after"
capture_snapshot "client" "$CLIENT_SERIAL" "after"

echo "=== Done. Results in $RESULTS_DIR/ ==="
echo "Review before/after frame-time, memory, thermal, battery, and logcat evidence."
echo "Record findings in docs/test-results/sm-t220-performance.md"
