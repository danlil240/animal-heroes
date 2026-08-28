#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT_BIN="${GODOT_BIN:-godot}"
RUN_DIR=$(mktemp -d)
cleanup() {
  status=$?
  if [[ "$status" -ne 0 ]]; then
    cat "$RUN_DIR/host.log" "$RUN_DIR/client.log" "$RUN_DIR/third.log" 2>/dev/null || true
  fi
  jobs -pr | xargs -r kill 2>/dev/null || true
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" -s res://tests/integration/test_session_pair.gd -- --role=host >"$RUN_DIR/host.log" 2>&1 &
host_pid=$!
sleep 0.4
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" -s res://tests/integration/test_session_pair.gd -- --role=client >"$RUN_DIR/client.log" 2>&1 &
client_pid=$!
sleep 0.4
"$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" -s res://tests/integration/test_session_pair.gd -- --role=third >"$RUN_DIR/third.log" 2>&1
wait "$client_pid"
wait "$host_pid"
grep -q 'SESSION_RESULT role=host state=playing character=rabbit level=crystal_caves' "$RUN_DIR/host.log"
grep -q 'SESSION_RESULT role=client state=playing character=fox level=crystal_caves' "$RUN_DIR/client.log"
grep -q 'SESSION_RESULT role=third accepted=false' "$RUN_DIR/third.log"
