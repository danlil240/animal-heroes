#!/usr/bin/env bash
# Resolve Android SDK executables without requiring a global PATH change.
set -euo pipefail

resolve_android_tools() {
  if [[ -x "${ADB_BIN:-}" && -x "${AAPT_BIN:-}" && -x "${APKSIGNER_BIN:-}" ]]; then
    export ADB_BIN AAPT_BIN APKSIGNER_BIN
    return 0
  fi

  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$sdk_root" && -d "$HOME/Android/Sdk" ]]; then
    sdk_root="$HOME/Android/Sdk"
  fi
  [[ -d "$sdk_root" ]] || { echo "Android SDK not found" >&2; return 2; }

  ADB_BIN="${ADB_BIN:-$sdk_root/platform-tools/adb}"
  local build_tools_dir="$sdk_root/build-tools"
  if [[ ! -d "$build_tools_dir" ]]; then
    echo "Android platform/build tools are incomplete" >&2
    return 2
  fi
  if [[ -z "${AAPT_BIN:-}" ]]; then
    AAPT_BIN="$(find "$build_tools_dir" -mindepth 2 -maxdepth 2 -type f -name aapt -print 2>/dev/null | sort -V | tail -n 1)" || true
  fi
  if [[ -z "${APKSIGNER_BIN:-}" ]]; then
    APKSIGNER_BIN="$(find "$build_tools_dir" -mindepth 2 -maxdepth 2 -type f -name apksigner -print 2>/dev/null | sort -V | tail -n 1)" || true
  fi
  [[ -x "$ADB_BIN" && -x "$AAPT_BIN" && -x "$APKSIGNER_BIN" ]] || { echo "Android platform/build tools are incomplete" >&2; return 2; }

  export ADB_BIN AAPT_BIN APKSIGNER_BIN
}
