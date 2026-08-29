#!/usr/bin/env bash
# Wireless ADB pairing helper for SM-T220 tablets.
# Walks the operator through pairing both tablets over wireless ADB and
# extracts the hardware serials needed for release/deploy_config.json.
#
# Prerequisites: Android SDK platform-tools (adb), both tablets on the same
# private LAN as the workstation, Developer Options > Wireless Debugging
# enabled on each tablet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/android_tools.sh"
resolve_android_tools

CONFIG_PATH="$ROOT_DIR/release/deploy_config.json"
PAIRED_FILE="${PAIRED_FILE:-$ROOT_DIR/release/paired_devices.json}"

# Reset the adb daemon to avoid stale state that causes "protocol fault" errors.
"$ADB_BIN" kill-server 2>/dev/null || true
"$ADB_BIN" start-server 2>/dev/null || true

pair_one() {
  local role="$1"
  echo ""
  echo "=== Pairing $role tablet ==="
  echo "On the $role tablet:"
  echo "  1. Settings > Developer Options > Wireless Debugging > ON"
  echo "  2. Tap 'Pair device with pairing code'"
  echo "  3. Note the IP:port and pairing code shown on screen"
  echo "  (The pairing port is one-time use — generate a fresh one for each attempt)"
  echo ""
  printf '  Enter the pair IP:port for %s: ' "$role"
  read -r pair_endpoint
  [[ -n "$pair_endpoint" ]] || { echo "Empty endpoint — skipping $role"; return 1; }
  echo "  Running: adb pair $pair_endpoint"
  local pair_output pair_rc
  pair_output="$("$ADB_BIN" pair "$pair_endpoint" 2>&1)" || true
  pair_rc=$?
  echo "$pair_output"
  if [[ $pair_rc -ne 0 ]] || ! grep -Fq "Successfully paired" <<<"$pair_output"; then
    echo "  ⚠ Pairing failed (exit $pair_rc)."
    echo "  The pairing port is one-time use. Generate a fresh pair code on the tablet,"
    echo "  run 'adb kill-server', then re-run this script."
    return 1
  fi
  echo ""
  echo "  Verifying connection..."
  printf '  Enter the tablet IP:port (connection port, not pair port) for %s: ' "$role"
  read -r conn_endpoint
  [[ -n "$conn_endpoint" ]] || { echo "Empty endpoint — skipping $role"; return 1; }
  local conn_output conn_rc
  conn_output="$("$ADB_BIN" connect "$conn_endpoint" 2>&1)" || true
  conn_rc=$?
  echo "$conn_output"
  if [[ $conn_rc -ne 0 ]] || ! grep -Fq "connected" <<<"$conn_output"; then
    echo "  ⚠ Connect failed (exit $conn_rc)."
    echo "  Check that the tablet is on the same LAN and the connection port is correct"
    echo "  (it's different from the pairing port — see the Wireless Debugging screen)."
    return 1
  fi

  # Extract hardware serial
  local model serial
  model="$("$ADB_BIN" -s "$conn_endpoint" shell getprop ro.product.model 2>/dev/null || true)"
  serial="$("$ADB_BIN" -s "$conn_endpoint" shell getprop ro.serialno 2>/dev/null || true)"
  serial="$(echo -n "$serial" | tr -d '[:space:]')"

  if [[ "$model" != "SM-T220" ]]; then
    echo "  ⚠ Device reports model '$model', expected SM-T220"
    return 1
  fi
  if [[ -z "$serial" ]]; then
    echo "  ⚠ Could not read hardware serial"
    return 1
  fi
  echo "  ✓ $role: SM-T220, serial=$serial"
  printf '%s\t%s\t%s\n' "$role" "$serial" "$conn_endpoint" >> "$PAIRED_FILE.tmp"
  return 0
}

echo "=== Wireless ADB Tablet Pairing ==="
echo "This helper pairs two SM-T220 tablets and extracts their hardware serials"
echo "for release/deploy_config.json."
echo ""

rm -f "$PAIRED_FILE.tmp"
touch "$PAIRED_FILE.tmp"

pair_one "host"   || echo "  Host pairing incomplete — re-run for host."
pair_one "client" || echo "  Client pairing incomplete — re-run for client."

echo ""
echo "=== Paired devices ==="
HOST_SERIAL=""
CLIENT_SERIAL=""
HOST_ENDPOINT=""
CLIENT_ENDPOINT=""
while IFS=$'\t' read -r role serial endpoint; do
  echo "  $role: serial=$serial endpoint=$endpoint"
  case "$role" in
    host)   HOST_SERIAL="$serial"; HOST_ENDPOINT="$endpoint" ;;
    client) CLIENT_SERIAL="$serial"; CLIENT_ENDPOINT="$endpoint" ;;
  esac
done < "$PAIRED_FILE.tmp"

mv "$PAIRED_FILE.tmp" "$PAIRED_FILE"
chmod 600 "$PAIRED_FILE"
echo ""
echo "Saved to: $PAIRED_FILE"

if [[ -n "$HOST_SERIAL" && -n "$CLIENT_SERIAL" ]]; then
  echo ""
  echo "=== Updating release/deploy_config.json ==="
  python3 - "$CONFIG_PATH" "$HOST_SERIAL" "$CLIENT_SERIAL" <<'PY'
import json, os, sys, tempfile
from pathlib import Path

config_path = Path(sys.argv[1])
host_serial = sys.argv[2]
client_serial = sys.argv[3]

if config_path.exists():
    data = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        data = {}
else:
    data = {}

data["devices"] = [
    {"role": "host", "hardware_id": host_serial},
    {"role": "client", "hardware_id": client_serial},
]

config_path.parent.mkdir(parents=True, exist_ok=True)
os.chmod(config_path.parent, 0o700)
content = json.dumps(data, indent=2, sort_keys=True) + "\n"
with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=config_path.parent,
                                 prefix=".deploy_config.", delete=False) as tmp:
    tmp.write(content)
    tmp.flush()
    os.fsync(tmp.fileno())
    tmp_path = Path(tmp.name)
os.chmod(tmp_path, 0o600)
os.replace(tmp_path, config_path)
print(f"  ✓ wrote device serials to {config_path}")
PY
  echo ""
  echo "=== Next steps ==="
  echo "  1. Fill lan_address, lan_port, dashboard_port, discovery_port in $CONFIG_PATH"
  echo "  2. Run: bash scripts/setup_keystore.sh (if not already done)"
  echo "  3. Run: HOST_SERIAL=$HOST_SERIAL CLIENT_SERIAL=$CLIENT_SERIAL bash scripts/device_smoke.sh"
  echo "  4. Run: HOST_SERIAL=$HOST_SERIAL CLIENT_SERIAL=$CLIENT_SERIAL bash scripts/endurance_matrix.sh"
else
  echo ""
  echo "⚠ One or both tablets not paired. Re-run this script to complete pairing."
  exit 1
fi
