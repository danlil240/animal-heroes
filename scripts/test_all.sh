#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
python3 scripts/sync_release_metadata.py --check
"$GODOT_BIN" --headless --editor --path game --quit
while IFS= read -r test_file; do
  "$GODOT_BIN" --headless --path game -s "res://${test_file#game/}"
done < <(find game/tests -name 'test_*.gd' -type f ! -name 'test_session_pair.gd' ! -name 'test_reconnect_pair.gd' | sort)
bash scripts/run_lan_pair.sh
bash scripts/run_reconnect_pair.sh
"$GODOT_BIN" --headless --path game -s res://tests/device/performance_check.gd
bash game/tests/device/test_apk_permissions.sh
bash game/tests/device/test_device_smoke.sh
