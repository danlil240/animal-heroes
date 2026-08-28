#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --editor --path game --quit
while IFS= read -r test_file; do
  "$GODOT_BIN" --headless --path game -s "res://${test_file#game/}"
done < <(find game/tests -name 'test_*.gd' -type f | sort)
