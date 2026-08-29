#!/usr/bin/env bash
# Persistent shell regression coverage for the dual-tablet capture harness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SMOKE_SCRIPT="$ROOT_DIR/scripts/device_smoke.sh"
TEMP_DIR="$(mktemp -d)"
SDK_DIR="$TEMP_DIR/sdk"
RESULTS_DIR="$TEMP_DIR/results"
RELEASE_RESULTS_DIR="$ROOT_DIR/docs/test-results"
RELEASE_RESULTS_SNAPSHOT="$TEMP_DIR/release-results.snapshot"
RELEASE_RESULTS_LINK="$TEMP_DIR/release-results-link"
ADB_LOG="$TEMP_DIR/adb.log"
EVENT_LOG="$TEMP_DIR/events.log"
REAL_SHA256SUM="$(command -v sha256sum)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$SDK_DIR/platform-tools" "$SDK_DIR/build-tools/1.0.0" "$TEMP_DIR/bin"
find "$RELEASE_RESULTS_DIR" -maxdepth 1 -type f -exec "$REAL_SHA256SUM" {} + 2>/dev/null | sort > "$RELEASE_RESULTS_SNAPSHOT"
ln -s "$RELEASE_RESULTS_DIR" "$RELEASE_RESULTS_LINK"

cat > "$SDK_DIR/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

serial=""
if [[ "${1:-}" == "-s" ]]; then
  serial="$2"
  shift 2
fi
printf '%s\t%s\n' "$serial" "$*" >> "$FAKE_ADB_LOG"
printf 'adb %s %s\n' "$serial" "$*" >> "$FAKE_EVENT_LOG"

if [[ "$*" == "shell getprop ro.product.model" ]]; then
  if [[ "$serial" == "client-serial" ]]; then
    printf '%s\n' "${FAKE_CLIENT_MODEL:-SM-T220}"
  else
    printf '%s\n' "${FAKE_HOST_MODEL:-SM-T220}"
  fi
elif [[ "$*" == install\ -r\ * ]]; then
  echo Success
fi
EOF
chmod +x "$SDK_DIR/platform-tools/adb"

cat > "$SDK_DIR/build-tools/1.0.0/aapt" <<'EOF'
#!/usr/bin/env bash
cat <<'PERMISSIONS'
package: org.danlil.animalheroes
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'
uses-permission: name='android.permission.INTERNET'
PERMISSIONS
EOF
chmod +x "$SDK_DIR/build-tools/1.0.0/aapt"

cat > "$TEMP_DIR/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sha256sum %s\n' "$*" >> "$FAKE_EVENT_LOG"
if [[ "${FAKE_SHA_MODE:-pass}" == "failure" ]]; then
  echo "fixture checksum failure" >&2
  exit 1
fi
exec "$REAL_SHA256SUM" "$@"
EOF
chmod +x "$TEMP_DIR/bin/sha256sum"

cat > "$TEMP_DIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >> "$FAKE_EVENT_LOG"
exit 0
EOF
chmod +x "$TEMP_DIR/bin/sleep"

assert_contains() {
  local expected="$1"
  local file="$2"
  if ! grep -Fqx "$expected" "$file"; then
    echo "FAIL: expected adb call: $expected" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_count() {
  local expected="$1"
  local count="$2"
  local file="$3"
  local actual
  actual="$(grep -Fxc "$expected" "$file" || true)"
  if [[ "$actual" != "$count" ]]; then
    echo "FAIL: expected $count calls of: $expected (got $actual)" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_ordered_events() {
  local previous=0
  local expected line
  for expected in "$@"; do
    line="$(grep -n -F "$expected" "$EVENT_LOG" | awk -F: -v previous="$previous" '$1 > previous { print $1; exit }')"
    if [[ -z "$line" ]]; then
      echo "FAIL: expected ordered event after line $previous: $expected" >&2
      cat "$EVENT_LOG" >&2
      exit 1
    fi
    previous="$line"
  done
}

run_smoke() {
  env \
    ANDROID_SDK_ROOT="$SDK_DIR" \
    FAKE_ADB_LOG="$ADB_LOG" \
    FAKE_EVENT_LOG="$EVENT_LOG" \
    REAL_SHA256SUM="$REAL_SHA256SUM" \
    PATH="$TEMP_DIR/bin:$PATH" \
    HOST_SERIAL=host-serial \
    CLIENT_SERIAL=client-serial \
    SMOKE_DURATION_SECONDS=0 \
    SMOKE_TEST_MODE=1 \
    SMOKE_RESULTS_DIR="$RESULTS_DIR" \
    "$@" \
    bash "$SMOKE_SCRIPT"
}

set +e
checksum_output="$(run_smoke FAKE_SHA_MODE=failure 2>&1)"
checksum_status=$?
set -e
if [[ "$checksum_status" -eq 0 ]]; then
  echo "FAIL: invalid APK checksum was accepted" >&2
  exit 1
fi
if ! grep -Fq "APK checksum verification failed" <<<"$checksum_output"; then
  echo "FAIL: checksum rejection did not explain verification failure" >&2
  printf '%s\n' "$checksum_output" >&2
  exit 1
fi
echo "PASS: invalid APK checksum is rejected before installation"

set +e
same_serial_output="$(run_smoke CLIENT_SERIAL=host-serial 2>&1)"
same_serial_status=$?
set -e
if [[ "$same_serial_status" -eq 0 ]]; then
  echo "FAIL: identical host and client serials were accepted" >&2
  exit 1
fi
if ! grep -Fq "must be different devices" <<<"$same_serial_output"; then
  echo "FAIL: same-serial rejection did not explain the dual-device requirement" >&2
  printf '%s\n' "$same_serial_output" >&2
  exit 1
fi
echo "PASS: identical host and client serials are rejected"

set +e
duration_output="$(env \
  ANDROID_SDK_ROOT="$SDK_DIR" \
  FAKE_ADB_LOG="$ADB_LOG" \
  FAKE_EVENT_LOG="$EVENT_LOG" \
  REAL_SHA256SUM="$REAL_SHA256SUM" \
  PATH="$TEMP_DIR/bin:$PATH" \
  HOST_SERIAL=host-serial \
  CLIENT_SERIAL=client-serial \
  SMOKE_DURATION_SECONDS=0 \
  SMOKE_RESULTS_DIR="$RESULTS_DIR" \
  bash "$SMOKE_SCRIPT" 2>&1)"
duration_status=$?
set -e
if [[ "$duration_status" -eq 0 ]]; then
  echo "FAIL: non-default duration was accepted outside test mode" >&2
  exit 1
fi
if ! grep -Fq "SMOKE_TEST_MODE=1" <<<"$duration_output"; then
  echo "FAIL: duration rejection did not explain the test-only guard" >&2
  printf '%s\n' "$duration_output" >&2
  exit 1
fi
echo "PASS: non-default duration is test-only"

set +e
release_results_output="$(env \
  ANDROID_SDK_ROOT="$SDK_DIR" \
  FAKE_ADB_LOG="$ADB_LOG" \
  FAKE_EVENT_LOG="$EVENT_LOG" \
  REAL_SHA256SUM="$REAL_SHA256SUM" \
  PATH="$TEMP_DIR/bin:$PATH" \
  HOST_SERIAL=host-serial \
  CLIENT_SERIAL=client-serial \
  SMOKE_DURATION_SECONDS=0 \
  SMOKE_TEST_MODE=1 \
  SMOKE_RESULTS_DIR="$ROOT_DIR/docs/test-results" \
  bash "$SMOKE_SCRIPT" 2>&1)"
release_results_status=$?
set -e
if [[ "$release_results_status" -eq 0 ]]; then
  echo "FAIL: test duration override was allowed to write release evidence" >&2
  exit 1
fi
if ! grep -Fq "outside release evidence" <<<"$release_results_output"; then
  echo "FAIL: release-results rejection did not explain the evidence guard" >&2
  printf '%s\n' "$release_results_output" >&2
  exit 1
fi
echo "PASS: test duration override cannot write release evidence"

set +e
dot_results_output="$(env \
  ANDROID_SDK_ROOT="$SDK_DIR" \
  FAKE_ADB_LOG="$ADB_LOG" \
  FAKE_EVENT_LOG="$EVENT_LOG" \
  REAL_SHA256SUM="$REAL_SHA256SUM" \
  PATH="$TEMP_DIR/bin:$PATH" \
  HOST_SERIAL=host-serial \
  CLIENT_SERIAL=client-serial \
  SMOKE_DURATION_SECONDS=0 \
  SMOKE_TEST_MODE=1 \
  SMOKE_RESULTS_DIR="$ROOT_DIR/docs/test-results/." \
  bash "$SMOKE_SCRIPT" 2>&1)"
dot_results_status=$?
set -e
if [[ "$dot_results_status" -eq 0 ]]; then
  echo "FAIL: dot release-results alias was accepted" >&2
  exit 1
fi
echo "PASS: dot release-results alias is rejected"

set +e
symlink_results_output="$(env \
  ANDROID_SDK_ROOT="$SDK_DIR" \
  FAKE_ADB_LOG="$ADB_LOG" \
  FAKE_EVENT_LOG="$EVENT_LOG" \
  REAL_SHA256SUM="$REAL_SHA256SUM" \
  PATH="$TEMP_DIR/bin:$PATH" \
  HOST_SERIAL=host-serial \
  CLIENT_SERIAL=client-serial \
  SMOKE_DURATION_SECONDS=0 \
  SMOKE_TEST_MODE=1 \
  SMOKE_RESULTS_DIR="$RELEASE_RESULTS_LINK" \
  bash "$SMOKE_SCRIPT" 2>&1)"
symlink_results_status=$?
set -e
if [[ "$symlink_results_status" -eq 0 ]]; then
  echo "FAIL: symlink release-results alias was accepted" >&2
  exit 1
fi
echo "PASS: symlink release-results alias is rejected"

for alias in "$ROOT_DIR/docs/test-results/." "$RELEASE_RESULTS_LINK"; do
  set +e
  default_alias_output="$(env \
    ANDROID_SDK_ROOT="$SDK_DIR" \
    FAKE_ADB_LOG="$ADB_LOG" \
    FAKE_EVENT_LOG="$EVENT_LOG" \
    REAL_SHA256SUM="$REAL_SHA256SUM" \
    PATH="$TEMP_DIR/bin:$PATH" \
    HOST_SERIAL=host-serial \
    CLIENT_SERIAL=client-serial \
    SMOKE_DURATION_SECONDS=600 \
    SMOKE_TEST_MODE=1 \
    SMOKE_RESULTS_DIR="$alias" \
    bash "$SMOKE_SCRIPT" 2>&1)"
  default_alias_status=$?
  set -e
  if [[ "$default_alias_status" -eq 0 ]]; then
    echo "FAIL: default-duration test alias was accepted: $alias" >&2
    exit 1
  fi
done
echo "PASS: default-duration test aliases are rejected"

set +e
wrong_model_output="$(run_smoke FAKE_CLIENT_MODEL=Not-SM-T220 2>&1)"
wrong_model_status=$?
set -e
if [[ "$wrong_model_status" -eq 0 ]]; then
  echo "FAIL: non-SM-T220 client was accepted" >&2
  exit 1
fi
if ! grep -Fq "must report exactly SM-T220" <<<"$wrong_model_output"; then
  echo "FAIL: wrong-model rejection did not explain the exact SM-T220 requirement" >&2
  printf '%s\n' "$wrong_model_output" >&2
  exit 1
fi
echo "PASS: non-SM-T220 client is rejected"

: > "$ADB_LOG"
: > "$EVENT_LOG"
successful_output="$(run_smoke)"
if ! grep -Fq "TEST ONLY: operator-driven 0-second gameplay interval" <<<"$successful_output"; then
  echo "FAIL: test run did not display the actual duration" >&2
  printf '%s\n' "$successful_output" >&2
  exit 1
fi

for serial in host-serial client-serial; do
  assert_count "$(printf '%s\tshell getprop ro.product.model' "$serial")" 3 "$ADB_LOG"
  for command in \
    "shell dumpsys gfxinfo org.danlil.animalheroes" \
    "shell dumpsys meminfo org.danlil.animalheroes" \
    "shell dumpsys thermalservice" \
    "shell dumpsys battery" \
    "logcat -d"; do
    assert_count "$(printf '%s\t%s' "$serial" "$command")" 2 "$ADB_LOG"
  done
done

assert_count "$(printf '%s\tshell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp' host-serial)" 1 "$ADB_LOG"
assert_count "$(printf '%s\tshell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp' client-serial)" 1 "$ADB_LOG"
assert_ordered_events \
  "sha256sum --check $ROOT_DIR/build/animal-heroes-debug.apk.sha256" \
  "adb host-serial install -r $ROOT_DIR/build/animal-heroes-debug.apk" \
  "adb host-serial shell getprop ro.product.model" \
  "adb host-serial shell dumpsys gfxinfo org.danlil.animalheroes" \
  "adb host-serial shell dumpsys meminfo org.danlil.animalheroes" \
  "adb host-serial shell dumpsys thermalservice" \
  "adb host-serial shell dumpsys battery" \
  "adb host-serial logcat -d" \
  "adb client-serial shell getprop ro.product.model" \
  "adb client-serial shell dumpsys gfxinfo org.danlil.animalheroes" \
  "adb client-serial shell dumpsys meminfo org.danlil.animalheroes" \
  "adb client-serial shell dumpsys thermalservice" \
  "adb client-serial shell dumpsys battery" \
  "adb client-serial logcat -d" \
  "adb host-serial shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp" \
  "adb client-serial shell am start -n org.danlil.animalheroes/org.godotengine.godot.GodotApp" \
  "sleep 0" \
  "adb host-serial shell getprop ro.product.model" \
  "adb host-serial shell dumpsys gfxinfo org.danlil.animalheroes" \
  "adb host-serial shell dumpsys meminfo org.danlil.animalheroes" \
  "adb host-serial shell dumpsys thermalservice" \
  "adb host-serial shell dumpsys battery" \
  "adb host-serial logcat -d" \
  "adb client-serial shell getprop ro.product.model" \
  "adb client-serial shell dumpsys gfxinfo org.danlil.animalheroes" \
  "adb client-serial shell dumpsys meminfo org.danlil.animalheroes" \
  "adb client-serial shell dumpsys thermalservice" \
  "adb client-serial shell dumpsys battery" \
  "adb client-serial logcat -d"

if [[ "$(<"$RESULTS_DIR/apk-sha256.txt")" != "$("$REAL_SHA256SUM" "$ROOT_DIR/build/animal-heroes-debug.apk" | awk '{print $1}')" ]]; then
  echo "FAIL: results did not record the exact APK SHA-256" >&2
  exit 1
fi
if [[ "$(<"$RESULTS_DIR/run-duration-seconds.txt")" != "0" ]]; then
  echo "FAIL: results did not record the actual test duration" >&2
  exit 1
fi
if ! cmp -s "$RELEASE_RESULTS_SNAPSHOT" <(find "$RELEASE_RESULTS_DIR" -maxdepth 1 -type f -exec "$REAL_SHA256SUM" {} + 2>/dev/null | sort); then
  echo "FAIL: fake-device test populated repository release results" >&2
  diff -u "$RELEASE_RESULTS_SNAPSHOT" <(find "$RELEASE_RESULTS_DIR" -maxdepth 1 -type f -exec "$REAL_SHA256SUM" {} + 2>/dev/null | sort) >&2 || true
  exit 1
fi

echo "PASS: checksum, ordered before/after captures, launches, actual duration, alias rejection, and results isolation are recorded"
