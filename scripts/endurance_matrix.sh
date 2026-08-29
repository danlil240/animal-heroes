#!/usr/bin/env bash
# Dual SM-T220 endurance matrix driver.
# Runs the seven endurance tests from docs/test-results/sm-t220-performance.md.
# Each test captures before/after evidence and records pass/fail.
# Gameplay segments are operator-driven: the script pauses and waits for the
# operator to confirm the gameplay interval completed.
#
# Prerequisites: Both tablets connected via adb (USB or wireless),
# debug APK built and installed via scripts/device_smoke.sh.
# Usage: HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/endurance_matrix.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${ENDURANCE_RESULTS_DIR:-$ROOT_DIR/docs/test-results/endurance}"

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

require_sm_t220() {
  local role="$1" serial="$2" model
  model="$("$ADB_BIN" -s "$serial" shell getprop ro.product.model)"
  if [[ "$model" != "SM-T220" ]]; then
    echo "ERROR: $role device $serial must report exactly SM-T220; got: $model" >&2
    exit 2
  fi
}

clear_logs() {
  "$ADB_BIN" -s "$HOST_SERIAL" logcat -c
  "$ADB_BIN" -s "$CLIENT_SERIAL" logcat -c
}

capture_evidence() {
  local test_name="$1" timing="$2"
  local dir="$RESULTS_DIR/$test_name"
  mkdir -p "$dir"
  for serial in "$HOST_SERIAL" "$CLIENT_SERIAL"; do
    local role="client"
    [[ "$serial" == "$HOST_SERIAL" ]] && role="host"
    local prefix="$dir/${role}-${timing}"
    "$ADB_BIN" -s "$serial" shell dumpsys gfxinfo org.danlil.animalheroes > "${prefix}-gfxinfo.txt"
    "$ADB_BIN" -s "$serial" shell dumpsys meminfo org.danlil.animalheroes > "${prefix}-meminfo.txt"
    "$ADB_BIN" -s "$serial" shell dumpsys battery > "${prefix}-battery.txt"
    "$ADB_BIN" -s "$serial" logcat -d > "${prefix}-logcat.txt"
  done
}

launch_app() {
  local serial="$1"
  "$ADB_BIN" -s "$serial" shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp
}

stop_app() {
  local serial="$1"
  "$ADB_BIN" -s "$serial" shell am force-stop org.danlil.animalheroes
}

operator_pause() {
  local prompt="$1"
  printf '  %s? Press Enter when done: ' "$prompt"
  read -r _ || true
}

confirm_pass() {
  local test_name="$1"
  local reply=""
  printf '  ? Did "%s" pass (no crash, no desync, FPS stayed above 30)? [y/N] ' "$test_name"
  read -r reply || true
  if [[ "$reply" =~ ^[Yy] ]]; then
    printf 'PASS\n' >> "$RESULTS_DIR/$test_name/result.txt"
    echo "  ✓ $test_name: PASS"
  else
    printf 'FAIL\n' >> "$RESULTS_DIR/$test_name/result.txt"
    echo "  ✗ $test_name: FAIL"
  fi
}

run_test() {
  local test_name="$1"
  local setup_fn="$2"
  local gameplay_prompt="$3"
  local duration="${4:-0}"

  echo ""
  echo "=== $test_name ==="
  mkdir -p "$RESULTS_DIR/$test_name"
  clear_logs
  capture_evidence "$test_name" "before"
  $setup_fn
  if [[ "$duration" -gt 0 ]]; then
    echo "  Operator-driven interval: $duration seconds"
    echo "  $gameplay_prompt"
    sleep "$duration"
  else
    operator_pause "$gameplay_prompt"
  fi
  capture_evidence "$test_name" "after"
  confirm_pass "$test_name"
}

# ── Setup: cooperative campaign ───────────────────────────────────────────
setup_coop_campaign() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
}

# ── Setup: competitive arena ──────────────────────────────────────────────
setup_competitive() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
}

# ── Setup: create/join cycles ─────────────────────────────────────────────
setup_create_join() {
  echo "  The operator will perform 25 create/join cycles."
  echo "  Host creates, client joins, both return to menu, repeat."
}

# ── Setup: Wi-Fi loss (short) ─────────────────────────────────────────────
setup_wifi_short() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
  echo "  Wait for a stable session, then toggle Wi-Fi off on the client for 5 seconds."
}

# ── Setup: Wi-Fi loss (long) ──────────────────────────────────────────────
setup_wifi_long() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
  echo "  Wait for a stable session, then toggle Wi-Fi off on the client for 16 seconds."
}

# ── Setup: sleep-wake ─────────────────────────────────────────────────────
setup_sleep_wake() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
  echo "  Wait for a stable session, then press power to sleep both tablets, wait 10s, wake."
}

# ── Setup: host termination ───────────────────────────────────────────────
setup_host_termination() {
  launch_app "$HOST_SERIAL"
  sleep 3
  launch_app "$CLIENT_SERIAL"
  echo "  Wait for a stable session, then force-stop the host app."
}

echo "=== Endurance Matrix ==="
echo "Host: $HOST_SERIAL"
echo "Client: $CLIENT_SERIAL"
require_sm_t220 "host" "$HOST_SERIAL"
require_sm_t220 "client" "$CLIENT_SERIAL"
mkdir -p "$RESULTS_DIR"

# Test 1: 45-minute cooperative campaign
run_test "45min-coop-campaign" setup_coop_campaign \
  "Host/join cooperative mode and play all 3 levels + boss for 45 minutes." 2700

# Test 2: 20 rounds per competitive arena
run_test "20rounds-competitive" setup_competitive \
  "Host/join each competitive arena (Star Race, Treasure Dash, Bubble Bounce) for 20 rounds total." 0

# Test 3: 25 create/join cycles
run_test "25-create-join-cycles" setup_create_join \
  "Perform 25 create/join cycles (host creates, client joins, both return to menu)." 0

# Test 4: Five 5-second Wi-Fi losses
run_test "five-5s-wifi-loss" setup_wifi_short \
  "Perform five 5-second Wi-Fi losses on the client with recovery between each." 0

# Test 5: One 16-second Wi-Fi loss
run_test "one-16s-wifi-loss" setup_wifi_long \
  "Perform one 16-second Wi-Fi loss on the client." 0

# Test 6: Host/client sleep-wake
run_test "sleep-wake" setup_sleep_wake \
  "Sleep both tablets for 10 seconds, then wake and verify session resumes." 0

# Test 7: Host termination
run_test "host-termination" setup_host_termination \
  "Force-stop the host app and verify the client handles it gracefully." 0

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "=== Endurance Matrix Summary ==="
PASS_COUNT=0
FAIL_COUNT=0
for test_dir in "$RESULTS_DIR"/*/; do
  test_name="$(basename "$test_dir")"
  result="$(cat "$test_dir/result.txt" 2>/dev/null || echo 'UNKNOWN')"
  echo "  $test_name: $result"
  if [[ "$result" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done
echo ""
echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
echo "Evidence: $RESULTS_DIR/"
echo ""
echo "Parse evidence with:"
echo "  python3 scripts/parse_smoke_results.py $RESULTS_DIR/<test-name> --duration <seconds>"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
