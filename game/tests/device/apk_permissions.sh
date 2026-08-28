#!/usr/bin/env bash
# Permission audit for the Animal Heroes APK.
# Fails unless the APK requests exactly the four allowed LAN permissions.
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

set +e
PERMISSIONS="$("$AAPT_BIN" dump permissions "$APK" 2>&1)"
AAPT_STATUS=$?
set -e

if [[ "$AAPT_STATUS" -ne 0 ]]; then
  echo "FAIL: unable to inspect APK permissions." >&2
  if [[ -n "$PERMISSIONS" ]]; then
    printf '%s\n' "$PERMISSIONS" >&2
  fi
  exit 1
fi

EXPECTED_PERMISSIONS="$(printf '%s\n' \
  android.permission.ACCESS_NETWORK_STATE \
  android.permission.ACCESS_WIFI_STATE \
  android.permission.CHANGE_WIFI_MULTICAST_STATE \
  android.permission.INTERNET | sort)"
ACTUAL_PERMISSIONS="$(sed -n "s/^uses-permission: name='\(android.permission.[^']*\)'.*/\1/p" <<<"$PERMISSIONS" | sort -u)"

if [[ "$ACTUAL_PERMISSIONS" != "$EXPECTED_PERMISSIONS" ]]; then
  echo "FAIL: APK permissions must exactly match the allowed LAN set." >&2
  echo "Expected:" >&2
  printf '%s\n' "$EXPECTED_PERMISSIONS" >&2
  echo "Actual:" >&2
  printf '%s\n' "$ACTUAL_PERMISSIONS" >&2
  exit 1
fi

echo "PASS: APK permissions exactly match the allowed LAN set."
if [[ -n "$PERMISSIONS" ]]; then
  printf '%s\n' "$PERMISSIONS"
fi
