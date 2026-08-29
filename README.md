# Animal Heroes

A cooperative and competitive two-player LAN game for children, built in Godot 4
with typed GDScript and deployed to two Samsung Galaxy Tab A7 Lite (SM-T220)
tablets over a household Wi-Fi network. The UI is Hebrew RTL with large touch
targets; the deployment pipeline signs, verifies, and ships APKs to the tablets
from a single workstation with no app store and no internet dependency.

**Status:** 1.0.0 release candidate. Automated tests pass; physical tablet
endurance, FPS validation, and supervised child usability sessions are pending
real hardware. See `docs/release-checklist.md` for the live gate status.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building the APK](#building-the-apk)
- [Testing](#testing)
- [Deployment and Dashboard](#deployment-and-dashboard)
- [Project Structure](#project-structure)
- [Configuration Reference](#configuration-reference)
- [Release Gates](#release-gates)
- [Recovery](#recovery)
- [Further Documentation](#further-documentation)

---

## Features

### Gameplay

- **Cooperative campaign** — three levels plus a boss:
  - Sunny Forest (4 checkpoints, 2 enemy types, bubble powerup)
  - Crystal Caves (moving platforms, paired switches, heavy push)
  - Cloud Factory (fans, conveyors, boss entrance, entity budgets)
  - Comical robot boss with a deterministic phase machine and checkpointed retries
- **Competitive modes** with synchronized rematch flow and a positive Hebrew
  results screen:
  - Star Race (4 checkpoints, 15-second grace period)
  - Treasure Dash (180-second timer, bounded collectible spawning)
  - Bubble Bounce (hit scoring with repeated-hit protection)
- **Players** — rabbit and fox profiles with health, respawn, coyote time, and
  jump buffering
- **Offline test arena** with partner indicator and independent cameras

### Networking

- UDP broadcast host discovery with compatibility filtering
- ENet host/client session lifecycle with an explicit state graph
- Host-authoritative input replication with interpolation and reconciliation
- Pause, reconnect, and confirmed checkpoint recovery (15-second retry window)

### Presentation

- Hebrew RTL main menu, tutorial, and touch controls (96+ px targets)
- Original child-friendly SVG art with layered parallax backgrounds and animated
  hero visuals — no copyrighted assets
- Audio director with independent Music/SFX buses and persisted settings
- Configured Android application icon

### Deployment

- Local release catalog with immutable, SHA-256-pinned APKs
- Release pipeline that builds, signs, verifies, and stages candidates
- Two-tablet deployment coordinator with rollback
- Pinned TLS tablet update client over the LAN
- Loopback dashboard for the operator; separate LAN API for the tablets
- Stable promotion gated on real evidence (no fake gates)

---

## Architecture

```
game/                      Godot 4 project (typed GDScript)
  autoload/                Singletons: SaveStore, AppState, Session
  core/                    Shared engine helpers
  levels/                  Coop + competitive arenas and the boss arena
  modes/                   Per-mode rules (coop, star race, treasure dash, ...)
  network/                 Discovery, protocol, session state, reconnect
  player/                  Player movement, profiles, health
  world/                   Interactables, enemies, object pool, powerups
  ui/                      Hebrew RTL shell, menus, results, touch controls
  visual/                  Visual target art and animations
  audio/                   Audio director and buses
  art/, assets/            SVG art, audio, ATTRIBUTION.md
  tests/                   unit / integration / device / support
  theme/                   Theme resources

deploy/                    Python 3.12 stdlib-only deployment service
  animal_heroes_deploy/    Catalog, pipeline, dashboard, LAN API, auth, TLS
  tests/                   unittest suite for the deploy service

scripts/                   Bash + Python orchestration
  build_android.sh         Deterministic APK build + permission audit
  test_all.sh              Full headless test runner
  device_smoke.sh          Dual-tablet before/after evidence capture
  pair_tablets.sh          Wireless ADB pairing helper
  setup_keystore.sh        Keystore + signer pin wizard
  endurance_matrix.sh      Endurance test matrix runner
  parse_smoke_results.py   Smoke evidence -> metrics table parser
  sync_release_metadata.py Toolchain version reconciliation
  run_lan_pair.sh          Two-process LAN session test
  run_reconnect_pair.sh    Two-process reconnect test
  android_tools.sh         SDK tool resolution

release/                   Release metadata and deploy config (secrets gitignored)
  metadata.json            Version, protocol, save schema
  gates.json               Stable-promotion evidence gates
  deploy_config.json       Operator config (created by setup wizard)

docs/                      Setup, build, release, and test-result docs
build/                     APK output (gitignored)
```

The game and the deploy service are intentionally decoupled: the game is a
standalone Godot project, and the deploy service is a zero-dependency Python
package that ships signed APKs to the tablets over the LAN. The only contract
between them is the APK in `build/` and the metadata in `release/`.

---

## Prerequisites

### Workstation (Ubuntu/GNOME)

- Python 3.12+ (standard library only — no pip packages)
- Git
- OpenSSL
- GNOME Keyring (`secret-tool` from `libsecret-tools`)
- OpenJDK 17
- Godot 4.7.2 with matching Android export templates
- Android SDK with:
  - `platform-tools/adb`
  - `build-tools/<version>/aapt` and `apksigner`
  - Android platforms API 34+

### Tablets

- Exactly two Samsung Galaxy Tab A7 Lite Wi-Fi (SM-T220)
- Wireless ADB enabled (Developer Options > Wireless Debugging)
- Both tablets on the same private LAN as the workstation

See `docs/android-build.md` for the full toolchain version matrix.

---

## Quick Start

Run the full headless test suite from the repo root:

```bash
bash scripts/test_all.sh
```

This runs the metadata check, imports the Godot project, executes every
`game/tests/**/test_*.gd`, runs the two-process LAN and reconnect pair tests,
verifies entity budgets, and exercises the APK permission audit and device smoke
contract under faked tools. All tests must pass.

To open the game in the Godot editor:

```bash
godot --editor --path game
```

---

## Building the APK

```bash
bash scripts/build_android.sh
```

This produces a deterministic debug APK and its SHA-256 checksum:

- `build/animal-heroes-debug.apk`
- `build/animal-heroes-debug.apk.sha256`

It also runs the permission audit, which enforces the exact LAN-only permission
set: `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
`CHANGE_WIFI_MULTICAST_STATE`, and `INTERNET` — nothing more.

A release APK requires a configured keystore; see
[Deployment and Dashboard](#deployment-and-dashboard) below.

---

## Testing

### Godot headless tests

```bash
godot --headless --path game -s res://tests/unit/test_<name>.gd
```

Test layout under `game/tests/`:

| Directory     | Purpose                                                                  |
| ------------- | ------------------------------------------------------------------------ |
| `unit/`       | Pure-logic rules: player, world, boss phases, modes, protocol, save, session state |
| `integration/`| Scene-level: app shell, arenas, connection overlay, levels              |
| `device/`     | APK permissions, performance/entity budgets, dual-tablet smoke contract |
| `support/`    | Shared assertions helper                                                 |

The two-process LAN and reconnect tests are driven by
`scripts/run_lan_pair.sh` and `scripts/run_reconnect_pair.sh` and are included
in `scripts/test_all.sh`.

### Entity budget verification

```bash
godot --headless --path game -s res://tests/device/performance_check.gd
```

Verifies the worst-case scene (Cloud Factory) stays within budget:
`enemy_budget <= 12`, `projectile_budget <= 24`, `particle_budget <= 80`.

### Deploy service tests

```bash
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v
```

Covers the catalog, pipeline, dashboard routes, LAN API, auth, TLS identity,
config validation, secrets handling, rollback, and the smoke-results parser.

### Dual-tablet smoke (requires real hardware)

```bash
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/device_smoke.sh
python3 scripts/parse_smoke_results.py docs/test-results
```

Captures before/after `gfxinfo`, `meminfo`, `battery`, `thermalservice`, and
`logcat` from both tablets, then parses them into the metrics table required by
`docs/test-results/sm-t220-performance.md`. The smoke interval is operator-driven:
during the capture window, host/join the game and traverse Cloud Factory on both
tablets. Launching the two app processes alone is not gameplay.

---

## Deployment and Dashboard

The deployment system is documented in detail in
`docs/deployment-setup.md`. The short version:

### One-time setup

1. **Resolve Android tools** (verifies `adb`, `aapt`, `apksigner`):

   ```bash
   source scripts/android_tools.sh
   resolve_android_tools
   ```

2. **Create the release keystore and pin the signer** — the wizard creates the
   keystore outside the repo, stores the password in GNOME Keyring, extracts the
   signer SHA-256, and writes the keystore fields into
   `release/deploy_config.json`:

   ```bash
   bash scripts/setup_keystore.sh
   ```

3. **Pair the tablets and fill the `devices` array** (needs both SM-T220s on the
   LAN with wireless debugging enabled):

   ```bash
   bash scripts/pair_tablets.sh
   ```

4. **Sanity check** (non-destructive, no server started):

   ```bash
   python3 -m deploy.animal_heroes_deploy --check
   ```

### Run the dashboard

```bash
python3 -m deploy.animal_heroes_deploy
```

The dashboard is a loopback-only HTTP server at
`http://127.0.0.1:<dashboard_port>`. It exposes:

| Route                | Method | Purpose                                  |
| -------------------- | ------ | ---------------------------------------- |
| `/health`            | GET    | Liveness probe                           |
| `/api/releases`      | GET    | List catalog releases                    |
| `/api/active`        | GET    | Currently active release                 |
| `/api/config`        | GET    | Package id, LAN/port, dashboard port, masked device ids |

Optional flags:

- `--check` — non-destructive config check, then exit
- `--config <path>` — use a config file other than `release/deploy_config.json`
- `--dashboard-port <n>` / `--lan-port <n>` — override ports from the config

The LAN tablet API (`/api/update/status`, `/api/update/request`) is bound on the
private LAN address and authenticated via a challenge-response signature scheme.
See `deploy/animal_heroes_deploy/dashboard_routes.py` and
`http_router.py` for the route definitions and the loopback/LAN split.

> **Note:** In the current tree, the LAN API socket is not yet bound by the
> launcher and the challenge verifier is a stub. The dashboard routes themselves
> are fully implemented and tested. Wire-up of the LAN listener and the real
> verifier is the remaining work to make tablets reach the service.

---

## Project Structure

```
animal-heroes/
├── game/                Godot 4 project
├── deploy/              Python deployment service + tests
├── scripts/             Build, test, smoke, pairing, and setup orchestration
├── release/             Metadata, gates, deploy config (secrets gitignored)
├── docs/                Setup, build, release, and test-result documentation
├── build/               APK output (gitignored)
├── CHANGELOG.md         Notable changes per release
└── README.md            This file
```

---

## Configuration Reference

`release/deploy_config.json` is created by the setup wizard and validated by
`DeployConfig.from_dict` in `deploy/animal_heroes_deploy/config.py`. Required
fields:

| Field                   | Type     | Constraints                                            |
| ----------------------- | -------- | ------------------------------------------------------ |
| `package_id`            | string   | Must be `org.danlil.animalheroes`                      |
| `lan_address`           | string   | Private IPv4, not loopback, not link-local             |
| `lan_port`              | int      | 1–65535                                                |
| `dashboard_port`        | int      | 1–65535                                                |
| `discovery_port`        | int      | 1–65535                                                |
| `keystore_path`         | string   | Absolute path, must be outside `state_root`            |
| `keystore_alias`        | string   | Non-empty                                              |
| `pinned_signer_sha256`  | string   | 64 lowercase hex characters                            |
| `devices`               | array    | Exactly 2: one `host`, one `client`, distinct hardware ids (6–32 alphanumeric) |
| `retention`             | string   | Must be `retain_all` in version one                    |
| `state_root`            | string?  | Optional state directory override                      |

Secret fields (`password`, `token`, `secret`, `key`, `passphrase`,
`keystore_password`, `api_key`) are rejected if present in the config — the
keystore password lives only in GNOME Keyring.

---

## Release Gates

Stable promotion requires real evidence for every gate in
`release/gates.json`. No gate may be marked passed without supporting evidence.

| Gate                              | Evidence                                              |
| --------------------------------- | ---------------------------------------------------- |
| `dual_sm_t220`                    | Two physical SM-T220 tablets verified                |
| `hebrew_review`                   | Hebrew text reviewed by a Hebrew reader              |
| `two_child_sessions`              | Two child usability sessions completed               |
| `audio_rights_or_replacement`     | Audio rights documented or replacements verified     |
| `keystore_backup`                 | Keystore backed up to a secure location              |
| `candidate_lineage_install_smoke` | Candidate install smoke test passed                  |

Current status: all gates `pending`. See `docs/release-checklist.md` for the
full acceptance criteria matrix and `docs/test-results/` for recorded results.

---

## Recovery

If the deployment service crashes during publication:

1. Check the operation journal in
   `$XDG_RUNTIME_DIR/animal-heroes-deploy/journal/`.
2. The catalog and Git refs are never modified until all preflight checks pass.
3. Staged worktrees are cleaned up on failure, or can be removed with
   `git worktree prune`.

If a deployment leaves the tablets in a version split:

1. The dashboard shows `VERSION_SPLIT` state.
2. Use "Retry failed device" to install only the failed tablet.
3. Never uninstall or clear app data as a recovery method.

If the minimum FPS falls below 30, optimize in this order (never alter
physics/network ticks to hide rendering cost):

1. Reduce particles/overdraw
2. Pool remaining allocations
3. Reduce active enemy/projectile caps
4. Compress oversized textures/audio
5. Lower render scale

---

## Further Documentation

- `docs/android-build.md` — Android toolchain matrix and export configuration
- `docs/deployment-setup.md` — Full deployment setup walkthrough
- `docs/release-checklist.md` — Release candidate acceptance criteria
- `docs/test-results/sm-t220-performance.md` — Tablet performance and endurance results
- `docs/test-results/child-usability.md` — Child usability test plan
- `CHANGELOG.md` — Notable changes per release
- `game/assets/ATTRIBUTION.md` — Audio provenance and rights
