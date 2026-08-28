#!/usr/bin/env bash
# Persistent shell regression coverage for the dual-tablet capture harness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SMOKE_SCRIPT="$ROOT_DIR/scripts/device_smoke.sh"
TEMP_DIR="$(mktemp -d)"
SDK_DIR="$TEMP_DIR/sdk"
RESULTS_DIR="$TEMP_DIR/results"
ADB_LOG="$TEMP_DIR/adb.log"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$SDK_DIR/platform-tools" "$SDK_DIR/build-tools/1.0.0" "$TEMP_DIR/bin"

cat > "$SDK_DIR/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

serial=""
if [[ "${1:-}" == "-s" ]]; then
  serial="$2"
  shift 2
fi
printf '%s\t%s\n' "$serial" "$*" >> "$FAKE_ADB_LOG"

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

cat > "$TEMP_DIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
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

run_smoke() {
  env \
    ANDROID_SDK_ROOT="$SDK_DIR" \
    FAKE_ADB_LOG="$ADB_LOG" \
    PATH="$TEMP_DIR/bin:$PATH" \
    HOST_SERIAL=host-serial \
    CLIENT_SERIAL=client-serial \
    SMOKE_DURATION_SECONDS=0 \
    SMOKE_RESULTS_DIR="$RESULTS_DIR" \
    "$@" \
    bash "$SMOKE_SCRIPT"
}

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
run_smoke

for serial in host-serial client-serial; do
  assert_contains "$(printf '%s\tshell getprop ro.product.model' "$serial")" "$ADB_LOG"
  for command in \
    "shell dumpsys gfxinfo org.danlil.animalheroes" \
    "shell dumpsys meminfo org.danlil.animalheroes" \
    "shell dumpsys thermalservice" \
    "shell dumpsys battery" \
    "logcat -d"; do
    assert_count "$(printf '%s\t%s' "$serial" "$command")" 2 "$ADB_LOG"
  done
done

echo "PASS: dual-SM-T220 capture commands run before and after the operator interval"
