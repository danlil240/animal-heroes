#!/usr/bin/env bash
# Shell regression coverage for the APK permission audit and Android tool resolver.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/apk_permissions.sh"
TEMP_DIR="$(mktemp -d)"
SDK_DIR="$TEMP_DIR/sdk"
APK="$TEMP_DIR/fixture.apk"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$SDK_DIR/platform-tools" "$SDK_DIR/build-tools/1.0.0"
touch "$APK"

cat > "$SDK_DIR/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SDK_DIR/platform-tools/adb"

cat > "$SDK_DIR/build-tools/1.0.0/aapt" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_AAPT_MODE:-exact}" in
  failure)
    echo "fixture aapt failure" >&2
    exit 41
    ;;
  exact)
    cat <<'PERMISSIONS'
package: org.danlil.animalheroes
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'
uses-permission: name='android.permission.INTERNET'
PERMISSIONS
    ;;
  extra)
    cat <<'PERMISSIONS'
package: org.danlil.animalheroes
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.BLUETOOTH_CONNECT'
PERMISSIONS
    ;;
  custom)
    cat <<'PERMISSIONS'
package: org.danlil.animalheroes
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='com.example.permission.SENSITIVE'
PERMISSIONS
    ;;
  sdk23)
    cat <<'PERMISSIONS'
package: org.danlil.animalheroes
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'
uses-permission: name='android.permission.INTERNET'
uses-permission-sdk-23: name='android.permission.POST_NOTIFICATIONS'
PERMISSIONS
    ;;
esac
EOF
chmod +x "$SDK_DIR/build-tools/1.0.0/aapt"

assert_case() {
  local name="$1"
  local expected_status="$2"
  local expected_text="$3"
  shift 3

  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    echo "FAIL: $name returned $status; expected $expected_status" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_text" <<<"$output"; then
    echo "FAIL: $name did not print: $expected_text" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  echo "PASS: $name"
}

assert_case "aapt failure is rejected" 1 "FAIL: unable to inspect APK permissions" \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" FAKE_AAPT_MODE=failure bash "$AUDIT_SCRIPT" "$APK"

assert_case "exact LAN permission set passes" 0 "PASS: APK permissions exactly match the allowed LAN set." \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" FAKE_AAPT_MODE=exact bash "$AUDIT_SCRIPT" "$APK"

assert_case "extra permission is rejected" 1 "FAIL: APK permissions must exactly match the allowed LAN set." \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" FAKE_AAPT_MODE=extra bash "$AUDIT_SCRIPT" "$APK"

assert_case "custom permission is rejected" 1 "FAIL: APK permissions must exactly match the allowed LAN set." \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" FAKE_AAPT_MODE=custom bash "$AUDIT_SCRIPT" "$APK"

assert_case "uses-permission-sdk-23 entry is rejected" 1 "FAIL: APK permissions must exactly match the allowed LAN set." \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" FAKE_AAPT_MODE=sdk23 bash "$AUDIT_SCRIPT" "$APK"

rm -rf "$SDK_DIR/build-tools"
assert_case "missing build-tools reports actionable diagnostic" 2 "Android platform/build tools are incomplete" \
  env -u ADB_BIN -u AAPT_BIN ANDROID_SDK_ROOT="$SDK_DIR" bash "$AUDIT_SCRIPT" "$APK"
