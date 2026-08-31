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
| 5 | Complete cooperative campaign (3 levels + boss) | `test_sunny_forest.gd`, `test_crystal_caves.gd`, `test_cloud_factory.gd`, `test_boss_phases.gd`, `test_sunny_forest_momentum_combat.gd` | PASS (automated, headless) |
| 6 | Three competitive modes with rematch | `test_star_race.gd`, `test_treasure_dash.gd`, `test_bubble_bounce.gd`, `test_results_flow.gd` | PASS (automated) |
| 7 | Hebrew RTL UI with touch controls | `test_hebrew_ui.gd` | PASS (automated) |
| 8 | Original child-friendly art, no copyrighted assets | Visual target acceptance record | PASS (desktop) |
| 9 | Configured Android application icon | `test_project_smoke.gd` and editor import | PASS (automated) |
| 10 | Audio creator and distribution rights recorded | `game/assets/ATTRIBUTION.md` provenance review | PENDING PROVENANCE CHECK |
| 11 | Child usability with minimal adult help | Supervised usability sessions | PENDING USABILITY CHECK |

## Build Artifacts

| Artifact | Status |
| --- | --- |
| `build/animal-heroes-debug.apk` | PASS — 2026-08-29; Godot 4.7.2.stable.official; 29,714,438 bytes; SHA-256 `f614d5d81fd9ab3cffa9707c5febc6d475550cd0c5d24af36865401316d51542` |
| `build/animal-heroes-debug.apk.sha256` | PASS — verified with `sha256sum --check` on 2026-08-29 |
| `build/animal-heroes-release.apk` | PENDING (no keystore) |
| `build/animal-heroes-release.apk.sha256` | PENDING |
| Permission audit (exact LAN permission set) | PASS — exactly `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, and `INTERNET` |

## Automated Test Suite

```bash
bash scripts/test_all.sh
```

All headless tests must pass. Current status: PASS.

## Pre-Release Steps

1. [ ] Record creator and distribution rights for every WAV asset
2. [ ] Build and verify debug APK
3. [ ] Run permission audit
4. [ ] Connect and authorize both SM-T220 tablets with ADB
5. [ ] Install on both SM-T220 tablets
6. [ ] Run endurance matrix on both tablets
7. [ ] Conduct supervised child usability sessions
8. [ ] Build signed release APK
9. [ ] Verify SHA-256 checksum
10. [ ] Install release on both tablets
11. [ ] Complete one cooperative checkpoint and one competitive match
12. [ ] Tag release: `git tag -a v1.0.0-rc1 -m "Animal Heroes 1.0.0 release candidate"`

## Sunny Forest Human/Hardware Gates

The following Sunny Forest acceptance gates require physical tablets and/or
supervised child sessions. They are intentionally recorded as NOT PASSED until
performed and evidenced; do not mark them passed without real evidence.

| # | Gate | Status |
| --- | --- | --- |
| SF-1 | Two children/operators complete the safe route together | NOT PASSED (requires supervised session) |
| SF-2 | One child/operator completes the fast route | NOT PASSED (requires supervised session) |
| SF-3 | Both find one secret without instruction | NOT PASSED (requires supervised session) |
| SF-4 | Both understand held fire without instruction | NOT PASSED (requires supervised session) |
| SF-5 | Both tablets maintain at least 30 FPS through Canopy Fork and Bubble Grove | NOT PASSED (requires SM-T220 tablets) |
