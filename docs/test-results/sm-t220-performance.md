# SM-T220 Performance and Endurance Results

Date: 2026-08-28
Target devices: Two Samsung Galaxy Tab A7 Lite Wi-Fi (SM-T220)
Renderer: Godot 4.7.2 Compatibility

## Status

**PENDING DEVICE CHECK.** The physical SM-T220 tablets are not available in the
current environment. The scripts and test harness are ready; results will be
recorded here once the devices are connected.

## Prerequisites

- Both tablets connected via USB with adb authorization
- Debug APK built via `scripts/build_android.sh`
- `adb`, `aapt`, and Android platform-tools installed

## Baseline Capture

Run:
```bash
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/device_smoke.sh
```

`device_smoke.sh` captures before/after device evidence, but its interval is
operator-driven: during the ten minutes, host/join the game and traverse Cloud
Factory on both tablets. Launching the two app processes alone is not gameplay.

Record the following for each device after that 10-minute Cloud Factory traversal:

| Metric | Tablet 1 (Host) | Tablet 2 (Client) |
| --- | --- | --- |
| Average FPS | PENDING | PENDING |
| Minimum FPS (1-second) | PENDING | PENDING |
| 99th percentile frame time | PENDING | PENDING |
| Peak memory (MB) | PENDING | PENDING |
| Thermal status | PENDING | PENDING |
| Battery change (%) | PENDING | PENDING |
| Reconnect count | PENDING | PENDING |
| Android errors/crashes | PENDING | PENDING |

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
