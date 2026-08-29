# SM-T220 Performance and Endurance Results

Date: 2026-08-28
Target devices: Two Samsung Galaxy Tab A7 Lite Wi-Fi (SM-T220)
Renderer: Godot 4.7.2 Compatibility

## Status

**PENDING DEVICE CHECK.** The physical SM-T220 tablets are not available in the
current environment. The scripts and test harness are ready; results will be
recorded here once the devices are connected.

## Prerequisites

- Both tablets connected via USB or wireless ADB with authorization
- Debug APK built via `scripts/build_android.sh`
- `adb`, `aapt`, and Android platform-tools installed

## Wireless Pairing (optional, for wireless ADB)

If using wireless ADB instead of USB, pair both tablets first:
```bash
bash scripts/pair_tablets.sh
```
This pairs each tablet, verifies it reports SM-T220, extracts the hardware
serial, and writes the `devices` array into `release/deploy_config.json`.

## Baseline Capture

Run:
```bash
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/device_smoke.sh
```

`device_smoke.sh` captures before/after device evidence, but its interval is
operator-driven: during the ten minutes, host/join the game and traverse Cloud
Factory on both tablets. Launching the two app processes alone is not gameplay.

Parse the captured evidence into the metrics table:
```bash
python3 scripts/parse_smoke_results.py docs/test-results
```

The parser reads `gfxinfo`, `meminfo`, `battery`, `thermalservice`, and
`logcat` captures, computes average FPS from the frame-count delta, extracts
percentile frame times, peak PSS, thermal status, battery change, and crash/
reconnect counts from logcat. Use `--format json` for machine-readable output.

Record the following for each device after that 10-minute Cloud Factory traversal:

| Metric | Tablet 1 (Host) | Tablet 2 (Client) |
| --- | --- | --- |
| Average FPS | PENDING | PENDING |
| 99th percentile frame time | PENDING | PENDING |
| 95th percentile frame time | PENDING | PENDING |
| Peak memory (MB) | PENDING | PENDING |
| Thermal status | PENDING | PENDING |
| Battery change (%) | PENDING | PENDING |
| Reconnect count | PENDING | PENDING |
| Crash count | PENDING | PENDING |

## Headless Entity Budget Verification

Run:
```bash
godot --headless --path game -s res://tests/device/performance_check.gd
```

This verifies the worst-case scene (Cloud Factory) stays within entity budgets:
- `enemy_budget <= 12`
- `projectile_budget <= 24`
- `particle_budget <= 80`

## Endurance Matrix

Run the full endurance matrix with:
```bash
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/endurance_matrix.sh
```

The driver captures before/after evidence per test and records pass/fail.
Gameplay segments are operator-driven: the script pauses and waits for the
operator to confirm the interval completed. Parse per-test evidence with:
```bash
python3 scripts/parse_smoke_results.py docs/test-results/endurance/<test-name> --duration <seconds>
```

The following matrix must pass with no crash, corrupt save, desync, or gameplay
interval below 30 FPS for more than one second:

| Test | Result |
| --- | --- |
| 45-minute cooperative campaign | PENDING DEVICE CHECK |
| 20 rounds per competitive arena | PENDING DEVICE CHECK |
| 25 create/join cycles | PENDING DEVICE CHECK |
| Five 5-second Wi-Fi losses | PENDING DEVICE CHECK |
| One 16-second Wi-Fi loss | PENDING DEVICE CHECK |
| Host/client sleep-wake | PENDING DEVICE CHECK |
| Host termination | PENDING DEVICE CHECK |

## Optimization Notes

If the minimum FPS falls below 30, optimize in this order:
1. Reduce particles/overdraw
2. Pool remaining allocations
3. Reduce active enemy/projectile caps
4. Compress oversized textures/audio
5. Lower render scale

Never alter physics/network ticks to hide rendering cost.
