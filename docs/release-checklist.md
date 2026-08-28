# Release Checklist

Animal Heroes 1.0.0 — Release Candidate

## Acceptance Criteria

Each criterion maps to an automated result, physical-device result, or
supervised usability result.

| # | Criterion | Verification method | Status |
| --- | --- | --- | --- |
| 1 | Two-player LAN play on SM-T220 tablets | Physical device endurance gate | PENDING DEVICE CHECK |
| 2 | Stable 30 FPS in worst-case scene | `performance_check.gd` + device smoke | PENDING DEVICE CHECK |
| 3 | Automatic UDP discovery and ENet connection | `test_discovery.gd`, `test_session_pair.gd` | PASS (automated) |
| 4 | Pause, reconnect, and checkpoint recovery | `test_reconnect_pair.gd`, `test_reconnect_state.gd` | PASS (automated) |
| 5 | Complete cooperative campaign (3 levels + boss) | `test_sunny_forest.gd`, `test_crystal_caves.gd`, `test_cloud_factory.gd`, `test_boss_phases.gd` | PASS (automated) |
| 6 | Three competitive modes with rematch | `test_star_race.gd`, `test_treasure_dash.gd`, `test_bubble_bounce.gd`, `test_results_flow.gd` | PASS (automated) |
| 7 | Hebrew RTL UI with touch controls | `test_hebrew_ui.gd` | PASS (automated) |
| 8 | Original child-friendly art, no copyrighted assets | Visual target acceptance record | PASS (desktop) |
| 9 | Child usability with minimal adult help | Supervised usability sessions | PENDING USABILITY CHECK |

## Build Artifacts

| Artifact | Status |
| --- | --- |
| `build/animal-heroes-debug.apk` | PENDING (no Android SDK) |
| `build/animal-heroes-debug.apk.sha256` | PENDING |
| `build/animal-heroes-release.apk` | PENDING (no keystore) |
| `build/animal-heroes-release.apk.sha256` | PENDING |
| Permission audit (no sensitive permissions) | PENDING (no APK) |

## Automated Test Suite

```bash
bash scripts/test_all.sh
```

All headless tests must pass. Current status: PASS.

## Pre-Release Steps

1. [ ] Install Android SDK and Godot export templates
2. [ ] Build and verify debug APK
3. [ ] Run permission audit
4. [ ] Install on both SM-T220 tablets
5. [ ] Run endurance matrix on both tablets
6. [ ] Conduct supervised child usability sessions
7. [ ] Build signed release APK
8. [ ] Verify SHA-256 checksum
9. [ ] Install release on both tablets
10. [ ] Complete one cooperative checkpoint and one competitive match
11. [ ] Tag release: `git tag -a v1.0.0-rc1 -m "Animal Heroes 1.0.0 release candidate"`
