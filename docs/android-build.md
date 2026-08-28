# Android Build Guide

This document records the prerequisites, configuration, and build steps for
exporting Animal Heroes to Android APK.

## Prerequisites

The following toolchain is installed in the release-candidate environment.

| Component | Required version | Detected version |
| --- | --- | --- |
| Godot Engine | 4.x stable (matching editor) | 4.7.2.stable.official |
| Godot Android export templates | Matching Godot version | 4.7.2.stable |
| Java/Javac | 17+ | OpenJDK 17.0.20.1 |
| Android platforms | API 34+ | 34 and 36 |
| Android build-tools | API 34+ | 34.0.0 and 36.1.0 |
| Android Debug Bridge (adb) | Platform tools | Installed; no connected, authorized device detected |
| aapt/aapt2 | Android build-tools | Installed with 34.0.0 and 36.1.0 |

> **Status:** The local build toolchain is ready. ADB installation is separate
> from device availability: no connected, authorized tablet was detected during
> this check. APK export, permission audit, and physical-device validation
> remain release gates.

## Export Configuration

The export preset lives at `game/export_presets.cfg`.

| Setting | Value |
| --- | --- |
| Package ID | `org.danlil.animalheroes` |
| Display name | Animal Heroes |
| Orientation | Landscape |
| Minimum API | 24 |
| Architecture | arm64-v8a |
| Permissions | `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` |

No camera, microphone, contacts, phone, location, SMS, or storage permissions
are requested. The permission audit script (`game/tests/device/apk_permissions.sh`)
fails the build if any of those appear in the compiled APK.

## Building

### Debug APK

```bash
bash scripts/build_android.sh
```

Produces `build/animal-heroes-debug.apk` and `build/animal-heroes-debug.apk.sha256`.
The build runs the APK permission audit before it writes the checksum.

### Android SDK tool resolution

The build, permission audit, and device smoke scripts source
`scripts/android_tools.sh`. They resolve the Android SDK executables in this
order: explicit executable overrides, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then
the conventional Linux path `$HOME/Android/Sdk`. No global `PATH` update is
required.

Use an SDK root override when the SDK lives elsewhere:

```bash
ANDROID_SDK_ROOT=/path/to/Android/Sdk bash scripts/build_android.sh
```

For a custom SDK layout, override both executable paths explicitly:

```bash
ADB_BIN=/path/to/adb AAPT_BIN=/path/to/aapt bash scripts/build_android.sh
```

`ADB_BIN` and `AAPT_BIN` must point to executable files. `GODOT_BIN` remains
available as a separate override for a Godot executable outside `PATH`.

### Release APK

Release builds require a keystore. Keep keystore credentials outside Git in the
local Godot editor/export environment.

```bash
mkdir -p build
godot --headless --path game --export-release Android build/animal-heroes-release.apk
sha256sum build/animal-heroes-release.apk | tee build/animal-heroes-release.apk.sha256
```

## Permission Audit

```bash
bash game/tests/device/apk_permissions.sh build/animal-heroes-debug.apk
```

The audit resolves `aapt` through the shared helper and exits non-zero if the
APK requests any sensitive permission.

## Installing on a Tablet

```bash
source scripts/android_tools.sh
resolve_android_tools
"$ADB_BIN" -s "$HOST_SERIAL" install -r build/animal-heroes-debug.apk
"$ADB_BIN" -s "$CLIENT_SERIAL" install -r build/animal-heroes-debug.apk
```

## Device Availability

Before the tablet checks, connect both SM-T220 devices by USB and authorize
ADB on each. Confirm availability with `"$ADB_BIN" devices -l`; this is a physical
test setup requirement, not an Android SDK installation check.
