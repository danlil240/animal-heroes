# AGENTS.md — Animal Heroes

Instructions for Devin (and other coding agents) working in this repo.
Read this before running builds, tests, or deployments.

## Quick reference

The four commands you'll reach for most often (run from the repo root):

```bash
bash scripts/test_all.sh                              # canonical "did I break anything" gate
bash scripts/build_android.sh                         # deterministic debug APK -> build/
python3 -m deploy.animal_heroes_deploy --check        # non-destructive deploy config check
HOST_SERIAL=<s> CLIENT_SERIAL=<s> bash scripts/device_smoke.sh   # dual-tablet smoke (real hw)
```

Resolve Android tools in any shell that needs adb/aapt/apksigner:

```bash
source scripts/android_tools.sh && resolve_android_tools
```

If a command fails, read its error and report it — don't paper over missing
toolchain pieces. See the sections below for the full debug/build/deploy flows.

## Project at a glance

- **Game:** Godot 4.7.2 project in `game/` (typed GDScript, Hebrew RTL, two-player LAN).
- **Deploy service:** Zero-dependency Python 3.12 stdlib package in `deploy/` that
  signs and ships APKs to two Samsung Galaxy Tab A7 Lite (SM-T220) tablets over the
  household LAN. No pip packages, no app store, no internet dependency.
- **Target tablets:** Exactly two SM-T220 (Wi-Fi), one `host`, one `client`.
- **Contract between game and deploy:** the APK in `build/` and metadata in
  `release/`. Nothing else.
- **Package id (fixed):** `org.danlil.animalheroes`. Never change it.
- **Allowed APK permissions (exact set, no more):** `INTERNET`,
  `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
  The permission audit fails the build on any deviation.

Full human-facing docs: `README.md`, `docs/android-build.md`,
`docs/deployment-setup.md`, `docs/release-checklist.md`.

## Environment prerequisites

Verify these exist before attempting builds or deploys. Do not silently install
system packages — tell the human partner what's missing.

- Python 3.12+ (stdlib only — never `pip install` anything in this repo).
- Git, OpenSSL, OpenJDK 17.
- GNOME Keyring + `secret-tool` (from `libsecret-tools`) — holds the keystore
  password; never write it to disk.
- Godot 4.7.2 with matching Android export templates.
- Android SDK with `platform-tools/adb`, `build-tools/<v>/aapt` and `apksigner`,
  platforms API 34+.
- Two SM-T220 tablets on the same private LAN, Wireless Debugging enabled.

Resolve Android tools in any shell that needs them:

```bash
source scripts/android_tools.sh
resolve_android_tools
echo "$ADB_BIN $AAPT_BIN $APKSIGNER_BIN"
```

`resolve_android_tools` exits 2 with a clear message if the SDK is incomplete —
do not paper over it; report it to the human partner.

## Verification commands (run these often)

These are the source of truth for "does it work". Run from the repo root.

```bash
# Full headless suite: metadata sync check, Godot import, all game/tests/**/test_*.gd,
# two-process LAN + reconnect pair tests, entity budgets, APK permission audit,
# device smoke contract under faked tools. Everything must pass.
bash scripts/test_all.sh

# Deploy service unit tests (catalog, pipeline, dashboard routes, LAN API, auth,
# TLS identity, config validation, secrets handling, rollback, smoke parser).
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v

# Non-destructive deploy config check (no server started).
python3 -m deploy.animal_heroes_deploy --check

# Single Godot test.
godot --headless --path game -s res://tests/unit/test_<name>.gd

# Entity budget check for the worst-case scene (Cloud Factory):
#   enemy_budget <= 12, projectile_budget <= 24, particle_budget <= 80.
godot --headless --path game -s res://tests/device/performance_check.gd
```

`scripts/test_all.sh` is the canonical "did I break anything" gate. The release
pipeline also runs it inside a staging worktree, so it must pass locally first.

## Debug workflow

1. **Reproduce reliably** before changing anything. For game logic, run the
   relevant `game/tests/**/test_*.gd` headless. For network behavior, use
   `scripts/run_lan_pair.sh` and `scripts/run_reconnect_pair.sh` (two-process,
   included in `test_all.sh`).
2. **Trace the code path.** Game code is under `game/` (autoload, core, levels,
   modes, network, player, world, ui). Deploy code is under
   `deploy/animal_heroes_deploy/`. Read the relevant module before editing.
3. **Add a failing test first** when fixing a bug (see the `tdd` skill). Game
   tests go in `game/tests/unit/` (pure logic) or `game/tests/integration/`
   (scene-level). Deploy tests go in `deploy/tests/test_*.py`.
4. **Fix**, then re-run the targeted test, then `bash scripts/test_all.sh`.
5. **For on-device bugs**, capture evidence with `adb` (see Device debugging
   below) — never guess at tablet behavior from logs you didn't collect.

### Device debugging (requires real tablets paired via adb)

```bash
# List connected tablets and their adb transport ids.
$ADB_BIN devices -l

# Model must be exactly SM-T220 — the smoke/endurance scripts enforce this.
$ADB_BIN -s <id> shell getprop ro.product.model

# App log output (Godot prints go through logcat).
$ADB_BIN -s <id> logcat -d | grep -i godot
$ADB_BIN -s <id> logcat -c   # clear before a fresh repro

# Frame timing, memory, thermal, battery snapshots (what the smoke script captures).
$ADB_BIN -s <id> shell dumpsys gfxinfo org.danlil.animalheroes
$ADB_BIN -s <id> shell dumpsys meminfo org.danlil.animalheroes
$ADB_BIN -s <id> shell dumpsys thermalservice
$ADB_BIN -s <id> shell dumpsys battery

# Launch / stop the app.
$ADB_BIN -s <id> shell am start -n org.danlil.animalheroes/com.godot.game.GodotAppLauncher
$ADB_BIN -s <id> shell am force-stop org.danlil.animalheroes
```

If minimum FPS drops below 30, optimize in this order and **never** alter
physics/network ticks to hide rendering cost:
1. Reduce particles/overdraw → 2. Pool remaining allocations →
3. Reduce active enemy/projectile caps → 4. Compress oversized textures/audio →
5. Lower render scale.

## Build workflow

### Debug APK (no keystore needed)

```bash
bash scripts/build_android.sh
```

Produces, deterministically:
- `build/animal-heroes-debug.apk`
- `build/animal-heroes-debug.apk.sha256`
- `build/animal-heroes-debug.apk.idsig` (v4 signature idsig)

It also runs the permission audit
(`game/tests/device/apk_permissions.sh`), which fails the build if the APK
requests anything outside the four allowed permissions. If the audit fails, fix
`game/export_presets.cfg` — do not weaken the audit.

`GODOT_BIN` can be overridden if `godot` isn't on PATH:
`GODOT_BIN=/path/to/godot bash scripts/build_android.sh`.

### Release APK (requires configured keystore)

Release APKs are only produced by the deploy service's release pipeline
(`deploy/animal_heroes_deploy/release_pipeline.py`), which exports with
`--export-release` using keystore credentials pulled from GNOME Keyring. Do not
hand-roll release exports; the pipeline pins the signer SHA-256 against
`release/deploy_config.json` and rejects mismatches.

## Deploy workflow

The deploy service is a loopback dashboard plus a (currently stubbed) LAN API
for the tablets. One-time setup is human-driven via wizards; day-to-day deploys
go through the dashboard.

### One-time setup (human-in-the-loop; use the `wizard` skill if re-running)

1. **Resolve Android tools** — `source scripts/android_tools.sh; resolve_android_tools`.
2. **Create the release keystore and pin the signer** — `bash scripts/setup_keystore.sh`.
   This creates the keystore outside the repo, stores the password in GNOME
   Keyring under `application=animal-heroes-deploy key=release-keystore-password`,
   extracts the signer SHA-256, and writes keystore fields into
   `release/deploy_config.json`. The password is never written to disk.
3. **Pair the tablets and fill the `devices` array** — `bash scripts/pair_tablets.sh`.
   Walks the operator through wireless ADB pairing on each SM-T220 and writes
   both hardware serials (one `host`, one `client`) into `deploy_config.json`.
4. **Sanity check** — `python3 -m deploy.animal_heroes_deploy --check` (non-destructive).

`release/deploy_config.json` is validated by `DeployConfig.from_dict` in
`deploy/animal_heroes_deploy/config.py`. Required fields and constraints are
documented in the README "Configuration Reference" section. Notable rules:
- `lan_address` must be a private IPv4 (not loopback, not link-local).
- `devices` must be exactly two: one `host`, one `client`, distinct hardware ids
  (6–32 alphanumeric).
- `retention` must be `retain_all` (version one).
- Secret-named fields (`password`, `token`, `secret`, `key`, `passphrase`,
  `keystore_password`, `api_key`) are **rejected** if present in the config.

### Running the dashboard

```bash
python3 -m deploy.animal_heroes_deploy
# Optional: --config <path> --dashboard-port <n> --lan-port <n>
```

Loopback-only HTTP server at `http://127.0.0.1:<dashboard_port>`. Routes:
`GET /health`, `GET /api/releases`, `GET /api/active`, `GET /api/config`.

> **Known gap:** the LAN API socket is not yet bound by the launcher and the
> challenge verifier is a stub (`__main__.py`). Dashboard routes are fully
> implemented and tested; wiring the LAN listener + real verifier is the
> remaining work for tablets to reach the service. Don't claim tablets can
> self-update until that's done.

### Deploying the active release to both tablets

Deployment is coordinated by `DeploymentCoordinator` in
`deploy/animal_heroes_deploy/deployment.py`, driven from the dashboard. It:
1. Reads the catalog's active release and its pinned APK.
2. Preflights both devices (resolves adb endpoint, probes battery/storage).
3. Force-stops the app on both, then installs the APK with one transport retry.
4. Verifies the installed `version_code` and `signer_sha256` match the active
   release on each tablet.
5. Returns `COMPLETE`, `VERSION_SPLIT` (one device failed or version mismatch),
   or `FAILED` (both failed).

For direct on-device install + evidence capture (bypassing the dashboard), use
the smoke script — see the next section.

### Dual-tablet smoke and endurance (requires real hardware)

```bash
# Build first.
bash scripts/build_android.sh

# Install the checksum-verified APK on both tablets and capture before/after
# gfxinfo/meminfo/battery/thermalservice/logcat. The 10-minute gameplay interval
# is OPERATOR-DRIVEN: host/join and traverse Cloud Factory on both tablets.
# Just launching the app processes is not gameplay.
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/device_smoke.sh
python3 scripts/parse_smoke_results.py docs/test-results

# Seven-test endurance matrix (45-min coop, 20 competitive rounds, 25 create/join
# cycles, Wi-Fi loss, sleep-wake, host termination). Also operator-driven.
HOST_SERIAL=<serial> CLIENT_SERIAL=<serial> bash scripts/endurance_matrix.sh
```

Both scripts enforce `ro.product.model == SM-T220` and refuse identical
host/client serials. `device_smoke.sh` verifies the APK SHA-256 before
installing and refuses to record evidence on a checksum mismatch. Non-default
`SMOKE_DURATION_SECONDS` requires `SMOKE_TEST_MODE=1` and a results dir outside
`docs/test-results` (test-only; never contaminate release evidence).

## Recovery

**Deploy service crash during publication:**
1. Check the operation journal in
   `$XDG_RUNTIME_DIR/animal-heroes-deploy/journal/`.
2. The catalog and Git refs are never modified until all preflight checks pass.
3. Staged worktrees are cleaned up on failure, or prune with `git worktree prune`.

**Version split between tablets:**
1. The dashboard shows `VERSION_SPLIT`.
2. Use "Retry failed device" (`DeploymentCoordinator.retry_failed_device`) to
   install only the failed tablet.
3. **Never** uninstall or clear app data as a recovery method.

## Hard rules for agents

- **No new third-party dependencies.** The deploy service is stdlib-only by
  design; the game is plain Godot. Don't add pip/cargo/asset dependencies.
- **Never write secrets to disk or commit them.** The keystore password lives
  only in GNOME Keyring. Secret-named config fields are rejected on purpose.
- **Never weaken the permission audit or the release gates.** The four
  permissions are the exact LAN-only set. `release/gates.json` gates stable
  promotion on real evidence — no gate may be marked passed without supporting
  evidence. See `docs/release-checklist.md`.
- **Never alter physics/network tick rates to hide rendering cost.** Use the
  FPS-recovery order above.
- **Never uninstall or clear app data on the tablets** as a recovery method.
- **Verify before claiming success.** Run `bash scripts/test_all.sh` and the
  deploy unit tests; paste real output, don't assert "it works" without evidence
  (see the `verification-before-completion` skill).
- **One problem per change.** Don't bundle unrelated edits; keep builds
  deterministic and the game/deploy contract (APK in `build/`, metadata in
  `release/`) intact.
- **Tablet operations are operator-driven.** Gameplay intervals in the smoke and
  endurance scripts require a human playing the game; launching the app process
  alone is not gameplay evidence.
