#!/usr/bin/env bash
# Deterministic Android APK build.
# Produces build/animal-heroes-debug.apk and its SHA-256 checksum.
#
# Prerequisites: Godot 4.x with Android export templates installed,
# Java JDK 17+, and Android SDK with build-tools. See docs/android-build.md.
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

mkdir -p "$BUILD_DIR"

echo "Building debug APK..."
"$GODOT_BIN" --headless --path "$ROOT_DIR/game" --export-debug Android "$BUILD_DIR/animal-heroes-debug.apk"

echo "Computing SHA-256..."
sha256sum "$BUILD_DIR/animal-heroes-debug.apk" > "$BUILD_DIR/animal-heroes-debug.apk.sha256"

echo "Done: $BUILD_DIR/animal-heroes-debug.apk"
cat "$BUILD_DIR/animal-heroes-debug.apk.sha256"
