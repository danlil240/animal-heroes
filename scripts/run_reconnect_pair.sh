#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT_BIN="${GODOT_BIN:-godot}"
RUN_DIR=$(mktemp -d)
cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" -s res://tests/integration/test_reconnect_pair.gd -- --role=host >"$RUN_DIR/host.log" 2>&1 &
host_pid=$!
sleep 0.4
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" -s res://tests/integration/test_reconnect_pair.gd -- --role=client >"$RUN_DIR/client.log" 2>&1 &
client_pid=$!
wait "$client_pid"
wait "$host_pid"
grep -q 'RECONNECT_RESULT role=host state=idle checkpoint=cp-1' "$RUN_DIR/host.log"
grep -q 'RECONNECT_RESULT role=client state=idle checkpoint=cp-1' "$RUN_DIR/client.log"
