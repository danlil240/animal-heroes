#!/usr/bin/env bash
# Permission audit for the Animal Heroes APK.
# Fails if the APK requests any sensitive permission.
# Usage: bash game/tests/device/apk_permissions.sh <path-to-apk>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/android_tools.sh"
resolve_android_tools

APK="${1:-}"
if [[ -z "$APK" || ! -f "$APK" ]]; then
  echo "Usage: $0 <path-to-apk>" >&2
  exit 2
fi

PERMISSIONS="$("$AAPT_BIN" dump permissions "$APK" 2>/dev/null || true)"

if grep -Eq \
  'CAMERA|RECORD_AUDIO|READ_CONTACTS|WRITE_CONTACTS|READ_PHONE|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|READ_SMS|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_EXTERNAL_STORAGE' \
  <<<"$PERMISSIONS"; then
  echo "FAIL: sensitive permissions detected in APK:" >&2
  printf '%s\n' "$PERMISSIONS" >&2
  exit 1
fi

echo "PASS: no sensitive permissions found."
if [[ -n "$PERMISSIONS" ]]; then
  printf '%s\n' "$PERMISSIONS"
fi
