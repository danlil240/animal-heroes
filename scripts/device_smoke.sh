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

# Wireless ADB devices are addressed by their mDNS transport id
# (e.g. adb-R83W80KJX5N-zWC9jb._adb-tls-connect._tcp), not the hardware serial.
# Map each hardware serial to its active adb transport id, falling back to the
# serial itself when no wireless transport is found (USB or fake-adb test mode).
resolve_adb_id() {
  local serial="$1"
  local adb_id
  adb_id="$("$ADB_BIN" devices 2>/dev/null | awk -v s="$serial" '
    $1 ~ s && $2 == "device" { print $1; exit }
  ')"
  if [[ -n "$adb_id" ]]; then
    echo "$adb_id"
  else
    echo "$serial"
  fi
}

HOST_ADB_ID="$(resolve_adb_id "$HOST_SERIAL")"
CLIENT_ADB_ID="$(resolve_adb_id "$CLIENT_SERIAL")"

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
  local adb_id="$2"
  local model
  model="$("$ADB_BIN" -s "$adb_id" shell getprop ro.product.model)"
  if [[ "$model" != "SM-T220" ]]; then
    echo "ERROR: $role device $adb_id must report exactly SM-T220; got: $model" >&2
    exit 2
  fi
}

capture_snapshot() {
  local role="$1"
  local adb_id="$2"
  local timing="$3"
  local prefix="$RESULTS_DIR/${role}-${timing}"

  "$ADB_BIN" -s "$adb_id" shell getprop ro.product.model > "${prefix}-model.txt"
  "$ADB_BIN" -s "$adb_id" shell dumpsys gfxinfo org.danlil.animalheroes > "${prefix}-gfxinfo.txt"
  "$ADB_BIN" -s "$adb_id" shell dumpsys meminfo org.danlil.animalheroes > "${prefix}-meminfo.txt"
  "$ADB_BIN" -s "$adb_id" shell dumpsys thermalservice > "${prefix}-thermalservice.txt"
  "$ADB_BIN" -s "$adb_id" shell dumpsys battery > "${prefix}-battery.txt"
  "$ADB_BIN" -s "$adb_id" logcat -d > "${prefix}-logcat.txt"
}

echo "=== Device check ==="
require_sm_t220 "host" "$HOST_ADB_ID"
require_sm_t220 "client" "$CLIENT_ADB_ID"

echo "=== Installing checksum-verified APK on both tablets ==="
"$ADB_BIN" -s "$HOST_ADB_ID" install -r "$APK"
"$ADB_BIN" -s "$CLIENT_ADB_ID" install -r "$APK"

echo "=== Permission audit ==="
bash "$ROOT_DIR/game/tests/device/apk_permissions.sh" "$APK"

echo "=== Clearing logs ==="
"$ADB_BIN" -s "$HOST_ADB_ID" logcat -c
"$ADB_BIN" -s "$CLIENT_ADB_ID" logcat -c

echo "=== Capturing before-run device evidence ==="
capture_snapshot "host" "$HOST_ADB_ID" "before"
capture_snapshot "client" "$CLIENT_ADB_ID" "before"

echo "=== Launching host ==="
"$ADB_BIN" -s "$HOST_ADB_ID" shell am start -n org.danlil.animalheroes/com.godot.game.GodotAppLauncher

echo "=== Launching client ==="
sleep 3
"$ADB_BIN" -s "$CLIENT_ADB_ID" shell am start -n org.danlil.animalheroes/com.godot.game.GodotAppLauncher

if [[ "$SMOKE_DURATION_SECONDS" == "$DEFAULT_SMOKE_DURATION_SECONDS" ]]; then
  echo "=== Operator-driven 10-minute gameplay interval (600 seconds) ==="
else
  echo "=== TEST ONLY: operator-driven ${SMOKE_DURATION_SECONDS}-second gameplay interval ==="
fi
echo "On both tablets, host/join the game and traverse Cloud Factory during this interval."
echo "Launching the app processes does not automatically perform gameplay."
sleep "$SMOKE_DURATION_SECONDS"

echo "=== Capturing after-run device evidence ==="
capture_snapshot "host" "$HOST_ADB_ID" "after"
capture_snapshot "client" "$CLIENT_ADB_ID" "after"

echo "=== Done. Results in $RESULTS_DIR/ ==="
echo "Review before/after frame-time, memory, thermal, battery, and logcat evidence."
echo "Record findings in docs/test-results/sm-t220-performance.md"
