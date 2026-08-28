# Android Build Guide

This document records the prerequisites, configuration, and build steps for
exporting Animal Heroes to Android APK.

## Prerequisites

The following toolchain is required to build the APK. Record the detected
versions here once the toolchain is installed.

| Component | Required version | Detected version |
| --- | --- | --- |
| Godot Engine | 4.x stable (matching editor) | 4.7.2.stable.official |
| Godot Android export templates | Matching Godot version | **NOT INSTALLED** |
| Java JDK | 17+ | **NOT INSTALLED** |
| Android SDK | API 34+ with build-tools | **NOT INSTALLED** |
| Android Debug Bridge (adb) | Platform tools | **NOT INSTALLED** |
| aapt | Android build-tools | **NOT INSTALLED** |

> **Status:** The Android SDK, Java JDK, and Godot Android export templates are
> not installed in the current environment. The build script and permission
> audit are ready but cannot produce an APK until these prerequisites are met.
> See the wizard section below for installation steps.

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

Exits non-zero if the APK requests any sensitive permission.

## Installing on a Tablet

```bash
adb -s "$HOST_SERIAL" install -r build/animal-heroes-debug.apk
adb -s "$CLIENT_SERIAL" install -r build/animal-heroes-debug.apk
```

## Wizard: Installing the Android Toolchain

Run the following wizard to install the missing prerequisites:

```bash
# Install Godot Android export templates
# In the Godot editor: Editor > Manage Export Templates > Download and Install
# Or manually copy templates to:
#   ~/.local/share/godot/export_templates/<version>/

# Install Java JDK
sudo apt install openjdk-17-jdk

# Install Android SDK command-line tools
# Download from https://developer.android.com/studio#command-line-tools-only
# Set ANDROID_HOME and install platform-tools, build-tools, and platforms
```
