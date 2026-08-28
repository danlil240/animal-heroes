# Animal Heroes Release-Candidate Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the feature-complete `main` branch into an evidence-backed Animal Heroes 1.0.0 release candidate for two SM-T220 tablets.

**Architecture:** Treat release readiness as a sequence of hard gates. Repair and expose the desktop LAN gate first, then complete presentation/build metadata, make Android tooling repeatable, run physical-device validation, conduct supervised usability checks, and only then sign and tag the release candidate. Measured device or usability defects return to the smallest relevant automated test before code changes.

**Tech Stack:** Godot 4.7.2, typed GDScript, ENet/UDP LAN networking, Bash release scripts, Android API 34/arm64-v8a, OpenJDK 17, Samsung Galaxy Tab A7 Lite Wi-Fi (SM-T220)

**Spec:** `docs/superpowers/specs/2026-08-27-animal-heroes-lan-game-design.md`

## Global Constraints

- Both tablets run the same APK; one hosts the authoritative session and one joins over local Wi-Fi.
- The release must work without internet services, accounts, advertisements, purchases, or online leaderboards.
- The target device is Samsung Galaxy Tab A7 Lite Wi-Fi, model SM-T220, in landscape orientation.
- Supported two-player gameplay must sustain at least 30 FPS on both target tablets.
- Menus and status copy remain Hebrew and right-to-left; controls remain icon-led and suitable for children aged four to five.
- Android permissions remain limited to `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, and `CHANGE_WIFI_MULTICAST_STATE`.
- Do not add game modes or campaign content during stabilization.
- Keep signing keys, passwords, tablet serials, and child-identifying information outside Git.

## Observed Baseline — 2026-08-29

- `main` is clean at `fccc8fa` and matches `origin/main`.
- All three feature branches are merged; their linked worktrees are clean but still present.
- The project contains 97 GDScript files, 39 scenes, and 30 nominal automated test scripts.
- `bash scripts/test_all.sh` exits successfully, but role-gated pair tests exit immediately when invoked without `--role`, so the result does not cover the real LAN pair paths.
- `bash scripts/run_lan_pair.sh` fails reproducibly: the host exits immediately after sending the chosen-level RPC, the client reports an empty `current_level_id`, and the third-client wrapper expects `IDLE` while the test permits any non-`PLAYING` state.
- `bash scripts/run_reconnect_pair.sh` passes.
- `performance_check.gd` passes its headless entity-budget gate.
- Debug APK export succeeds and produces a roughly 29 MB APK; the permission audit passes. Export reports that no application icon is configured.
- Godot 4.7.2, matching Android export templates, OpenJDK 17, Android SDK platforms 34/36, `adb`, and `aapt` are installed. `adb`/`aapt` are not on the default shell `PATH`.
- No Android device is currently attached.
- Release docs still claim Java/templates are absent and audio files are silent stubs; both statements are stale.
- Headless test processes emit ObjectDB/resource cleanup warnings after otherwise successful assertions. Track this as non-blocking test-harness debt unless it obscures a real failing exit status.

---

### Task 1: Make Multi-Process LAN Checks a Real Release Gate

**Files:**
- Modify: `game/autoload/session.gd`
- Modify: `game/tests/integration/test_session_pair.gd`
- Modify: `scripts/run_lan_pair.sh`
- Modify: `scripts/run_reconnect_pair.sh`
- Modify: `scripts/test_all.sh`

**Interfaces:**
- Consumes: `Session.start_level(level_id: String) -> void` and the existing role-based pair test entry points.
- Produces: `Session.level_start_acknowledged(peer_id: int, level_id: String)` and a full-suite command that executes both multi-process tests plus the entity-budget check.

- [ ] **Step 1: Preserve the failing LAN evidence**

Run:

```bash
bash scripts/run_lan_pair.sh
```

Expected: exit `1`. A diagnostic run of the three roles must show the client error `client did not receive the host's level, got ''`.

- [ ] **Step 2: Add a failing acknowledgement contract**

In `test_session_pair.gd`, connect the host to a new `level_start_acknowledged` signal before calling `start_level()`. Keep the host alive until the acknowledgement arrives or a three-second deadline expires:

```gdscript
var acknowledged_level := ""

func _capture_level_ack(_peer_id: int, level_id: String) -> void:
	acknowledged_level = level_id
```

The host role must fail with `host did not receive the client's level acknowledgement` when `acknowledged_level != SHARED_LEVEL` at the deadline. The third role must print `accepted=false` after proving it never reached `PLAYING`; it must not require a particular transient rejection state.

- [ ] **Step 3: Run the focused test and verify the new contract fails**

Run:

```bash
bash scripts/run_lan_pair.sh
```

Expected: FAIL because `Session.level_start_acknowledged` does not exist.

- [ ] **Step 4: Implement the minimal reliable acknowledgement**

Add to `session.gd`:

```gdscript
signal level_start_acknowledged(peer_id: int, level_id: String)

@rpc("any_peer", "reliable")
func acknowledge_level_start(level_id: String) -> void:
	if not _is_host or level_id != current_level_id:
		return
	level_start_acknowledged.emit(multiplayer.get_remote_sender_id(), level_id)
```

At the end of the client-side `deliver_level_start()`, call:

```gdscript
if not _is_host and _peer != null:
	acknowledge_level_start.rpc_id(1, level_id)
```

Do not delay production gameplay or add another screen; the acknowledgement exists to make delivery observable and testable.

- [ ] **Step 5: Make wrapper failures self-explanatory**

Update both pair scripts so an `EXIT` trap prints the host/client/third logs when the command status is non-zero, then removes the temporary directory. Change the third-client assertion in `run_lan_pair.sh` to:

```bash
grep -q 'SESSION_RESULT role=third accepted=false' "$RUN_DIR/third.log"
```

- [ ] **Step 6: Put all non-device gates behind one command**

In `scripts/test_all.sh`, skip direct no-role invocation of `test_session_pair.gd` and `test_reconnect_pair.gd`, then append:

```bash
bash scripts/run_lan_pair.sh
bash scripts/run_reconnect_pair.sh
"$GODOT_BIN" --headless --path game -s res://tests/device/performance_check.gd
```

This makes `bash scripts/test_all.sh` mean unit, single-process integration, LAN pair, reconnect pair, and headless performance budgets.

- [ ] **Step 7: Verify and commit the gate**

Run:

```bash
bash scripts/test_all.sh
```

Expected: exit `0`, with host and client both reporting `level=crystal_caves`, the third role reporting `accepted=false`, both reconnect roles reporting `checkpoint=cp-1`, and the performance check exiting successfully.

Commit:

```bash
git add game/autoload/session.gd game/tests/integration/test_session_pair.gd scripts/run_lan_pair.sh scripts/run_reconnect_pair.sh scripts/test_all.sh
git commit -m "test: enforce multi-process LAN release gates"
```

---

### Task 2: Complete Release Presentation Metadata and Asset Truth

**Files:**
- Create: `game/art/ui/app_icon.svg`
- Modify: `game/project.godot`
- Modify: `game/tests/unit/test_project_smoke.gd`
- Modify: `game/assets/ATTRIBUTION.md`
- Modify: `docs/android-build.md`
- Modify: `docs/release-checklist.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the approved bright, rounded rabbit/fox visual language and current original WAV assets.
- Produces: `application/config/icon="res://art/ui/app_icon.svg"` and release documentation that matches the repository and installed toolchain.

- [ ] **Step 1: Add a failing application-icon contract**

Extend `test_project_smoke.gd` with:

```gdscript
var icon_path := String(ProjectSettings.get_setting("application/config/icon", ""))
if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
	push_error("the Android release must configure a loadable application icon")
	quit(1)
	return
```

- [ ] **Step 2: Verify the icon contract fails**

Run:

```bash
godot --headless --path game -s res://tests/unit/test_project_smoke.gd
```

Expected: FAIL because `application/config/icon` is absent.

- [ ] **Step 3: Create and configure the icon**

Create a square, filter-free SVG with a `1024 1024` viewBox, opaque sky-blue background, high-contrast rabbit and fox head silhouettes, and no text, fonts, embedded images, or third-party marks. Configure it in `project.godot`:

```ini
[application]

config/name="Animal Heroes"
config/icon="res://art/ui/app_icon.svg"
run/main_scene="res://ui/game_shell.tscn"
```

- [ ] **Step 4: Reconcile asset and toolchain documentation**

Listen to all six WAV files once and record their actual role and authorship in `game/assets/ATTRIBUTION.md`; remove the silent-stub table only after confirming each asset is releasable. Update `docs/android-build.md` with these detected versions:

```text
Godot Engine: 4.7.2.stable.official
Godot Android export templates: 4.7.2.stable
Java/Javac: OpenJDK 17.0.20.1
Android platforms: 34 and 36
Android build-tools: 34.0.0 and 36.1.0
```

Keep ADB/device availability separate from installation status. Update the changelog and release checklist so audio, icon, build readiness, and remaining physical/human gates agree across all files.

- [ ] **Step 5: Verify icon import and documentation consistency**

Run:

```bash
godot --headless --editor --path game --quit
godot --headless --path game -s res://tests/unit/test_project_smoke.gd
rg -n 'silent|stub|NOT INSTALLED|no Android SDK|no project icon' game/assets/ATTRIBUTION.md docs/android-build.md docs/release-checklist.md CHANGELOG.md
```

Expected: the smoke test passes and `rg` returns no stale release claims.

- [ ] **Step 6: Commit**

```bash
git add game/art/ui/app_icon.svg game/project.godot game/tests/unit/test_project_smoke.gd game/assets/ATTRIBUTION.md docs/android-build.md docs/release-checklist.md CHANGELOG.md
git commit -m "chore: complete release presentation metadata"
```

---

### Task 3: Make Android Build and Permission Validation Repeatable

**Files:**
- Create: `scripts/android_tools.sh`
- Modify: `scripts/build_android.sh`
- Modify: `scripts/device_smoke.sh`
- Modify: `game/tests/device/apk_permissions.sh`
- Modify: `docs/android-build.md`
- Modify: `docs/release-checklist.md`

**Interfaces:**
- Produces: `resolve_android_tools() -> shell status`, `ADB_BIN`, and `AAPT_BIN` without requiring global `PATH` mutation.
- Produces: `build/animal-heroes-debug.apk` and `build/animal-heroes-debug.apk.sha256`, followed by an automatic permission audit.

- [ ] **Step 1: Capture the current path-dependent failure**

Build the current debug APK, then run its audit in a shell where Android SDK tools are not on `PATH`:

```bash
bash scripts/build_android.sh
env -u ANDROID_HOME -u ANDROID_SDK_ROOT PATH=/usr/bin:/bin bash game/tests/device/apk_permissions.sh build/animal-heroes-debug.apk
```

Expected: exit `2` with `aapt not found`, despite the SDK being installed under the configured Android SDK root.

- [ ] **Step 2: Implement one Android tool resolver**

Create `scripts/android_tools.sh` with `set -euo pipefail` and a `resolve_android_tools` function. Resolution order must be explicit overrides, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then the conventional Linux SDK directory. It must export executable paths and fail with one actionable message:

```bash
resolve_android_tools() {
  if [[ -x "${ADB_BIN:-}" && -x "${AAPT_BIN:-}" ]]; then
    export ADB_BIN AAPT_BIN
    return 0
  fi
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$sdk_root" && -d "$HOME/Android/Sdk" ]]; then
    sdk_root="$HOME/Android/Sdk"
  fi
  [[ -d "$sdk_root" ]] || { echo "Android SDK not found" >&2; return 2; }
  ADB_BIN="${ADB_BIN:-$sdk_root/platform-tools/adb}"
  if [[ -z "${AAPT_BIN:-}" ]]; then
    AAPT_BIN="$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name aapt -print | sort -V | tail -n 1)"
  fi
  [[ -x "$ADB_BIN" && -x "$AAPT_BIN" ]] || { echo "Android platform/build tools are incomplete" >&2; return 2; }
  export ADB_BIN AAPT_BIN
}
```

- [ ] **Step 3: Route every Android script through the resolver**

Source the helper from `build_android.sh`, `device_smoke.sh`, and `apk_permissions.sh`. Replace direct `adb`/`aapt` calls with `"$ADB_BIN"`/`"$AAPT_BIN"`. After debug export, `build_android.sh` must run the permission audit before writing the checksum.

- [ ] **Step 4: Build and audit the debug APK from a clean artifact directory**

Run:

```bash
bash scripts/build_android.sh
sha256sum --check build/animal-heroes-debug.apk.sha256
```

Expected: export succeeds without the missing-icon error, permission audit lists only the four allowed LAN permissions, and checksum verification passes.

- [ ] **Step 5: Record the reproducible build evidence**

Update the debug APK and checksum rows in `docs/release-checklist.md` to `PASS`, including the build date, Godot version, file size, and SHA-256. Document `ANDROID_SDK_ROOT`, `ADB_BIN`, and `AAPT_BIN` overrides in `docs/android-build.md` without hard-coding credentials or device serials.

- [ ] **Step 6: Run the full desktop gate and commit**

```bash
bash scripts/test_all.sh
git add scripts/android_tools.sh scripts/build_android.sh scripts/device_smoke.sh game/tests/device/apk_permissions.sh docs/android-build.md docs/release-checklist.md
git commit -m "build: make Android validation repeatable"
```

---

### Task 4: Pass Dual-SM-T220 Functional, Performance, and Endurance Gates

**Files:**
- Modify: `scripts/device_smoke.sh`
- Modify: `docs/test-results/sm-t220-performance.md`
- Modify: `docs/release-checklist.md`
- Test as measured: the smallest relevant files under `game/tests/`
- Modify only if measured: the smallest relevant runtime files under `game/network/`, `game/world/`, `game/visual/`, or `game/ui/`

**Interfaces:**
- Consumes: two explicitly identified, ADB-authorized SM-T220 tablets and the audited debug APK.
- Produces: host/client logs plus FPS, frame-time, memory, thermal, battery, reconnect, sleep/wake, and endurance evidence tied to the exact APK checksum.

- [ ] **Step 1: Make the capture script match its claim**

Before device execution, extend `device_smoke.sh` to reject non-SM-T220 devices and capture these commands for each tablet before and after the ten-minute run:

```bash
"$ADB_BIN" -s "$serial" shell getprop ro.product.model
"$ADB_BIN" -s "$serial" shell dumpsys gfxinfo org.danlil.animalheroes
"$ADB_BIN" -s "$serial" shell dumpsys meminfo org.danlil.animalheroes
"$ADB_BIN" -s "$serial" shell dumpsys thermalservice
"$ADB_BIN" -s "$serial" shell dumpsys battery
"$ADB_BIN" -s "$serial" logcat -d
```

Label the ten-minute interval as operator-driven: during it, host/join the game and traverse Cloud Factory on both tablets. Do not claim that launching two app processes automatically performs gameplay.

- [ ] **Step 2: Identify and install on both tablets**

```bash
source scripts/android_tools.sh
resolve_android_tools
"$ADB_BIN" devices -l
HOST_SERIAL="$SM_T220_HOST_SERIAL" CLIENT_SERIAL="$SM_T220_CLIENT_SERIAL" bash scripts/device_smoke.sh
```

Expected: both model checks return exactly `SM-T220`, both installs succeed, discovery joins without manual IP entry, and the permission audit passes on the same debug APK checksum recorded in the release checklist.

- [ ] **Step 3: Record the performance baseline before optimizing**

Complete the metric table in `docs/test-results/sm-t220-performance.md` with average FPS, minimum one-second FPS, 99th-percentile frame time, peak memory, thermal state, battery delta, reconnect count, and Android errors for both host and client. If the minimum drops below 30 FPS for more than one second, attach the scene/action and timestamp that caused it.

- [ ] **Step 4: Fix only reproduced device defects**

For each measured defect:

1. Add the smallest headless or multi-process regression test that reproduces the rule.
2. Run it and capture the expected failure.
3. Apply one focused runtime change.
4. Run the focused test, `bash scripts/test_all.sh`, rebuild the APK, repeat the device scenario, and record before/after metrics.

Optimize in this order only when evidence points to rendering cost: overdraw/particles, runtime allocations/pooling, active entity caps, texture/audio size, then render scale. Do not change physics or networking ticks to hide rendering cost.

- [ ] **Step 5: Complete the endurance matrix**

Run and record:

```text
1 complete 45-minute cooperative campaign
20 rounds of Star Race
20 rounds of Treasure Dash
20 rounds of Bubble Bounce
25 create/join cycles
5 separate 5-second Wi-Fi losses
1 16-second Wi-Fi loss
host sleep/wake and client sleep/wake
host termination followed by checkpoint recovery into a new session
```

Pass condition: no crash, corrupt save, desync, unrecoverable child-facing flow, or gameplay interval below 30 FPS for more than one second.

- [ ] **Step 6: Commit measured evidence and any focused fixes**

```bash
git add scripts/device_smoke.sh docs/test-results/sm-t220-performance.md docs/release-checklist.md game
git commit -m "perf: pass dual SM-T220 release gate"
```

If no runtime fix was needed, omit `game` from `git add` and use `test: record dual SM-T220 release evidence`.

---

### Task 5: Pass Native Hebrew and Supervised Child-Usability Gates

**Files:**
- Modify: `docs/test-results/child-usability.md`
- Modify: `docs/release-checklist.md`
- Test as observed: the smallest relevant file under `game/tests/integration/`
- Modify only if observed: the smallest relevant file under `game/ui/`

**Interfaces:**
- Consumes: the device-validated debug APK and the seven-task usability script already listed in `child-usability.md`.
- Produces: native-Hebrew approval and two supervised, non-identifying child-usability result columns with every blocker resolved or explicitly failed.

- [ ] **Step 1: Complete a native-Hebrew copy review on device**

Review every menu, connection state, tutorial instruction, pause/result label, level title, score label, and error message for vocabulary suitable for ages four to five, correct right-to-left layout, and punctuation. Record reviewer role and date, not a personal identifier. Add any wording defect to the observed-blockers section before changing code.

- [ ] **Step 2: Run two supervised sessions**

Observe each child independently attempting: create/join, Sunny Forest completion, Star Race, Treasure Dash, Bubble Bounce, recovery from a fall, and rematch. Record only `PASS`, `PROMPTED`, or `BLOCKED` plus the screen/action where prompting was required. Collect no names, audio, video, or behavioral profile.

- [ ] **Step 3: Convert every blocker into a failing regression test**

For each observed blocker, stop this release plan and open a bounded bugfix task containing the exact screen, action, expected behavior, observed behavior, and device resolution. Use `superpowers:systematic-debugging` to identify the cause, then `superpowers:test-driven-development` to add a focused failing test before changing UI code. Resume this plan only after the focused test proves the observed behavior is fixed; do not make speculative UI changes.

- [ ] **Step 4: Apply and verify the smallest fixes**

For each blocker, run the focused failing test, change only the responsible UI/input code, rerun the focused test and full suite, rebuild/reinstall the APK, then repeat the failed usability task. Commit independently meaningful fixes separately so a reviewer can accept or reject each one.

- [ ] **Step 5: Close the human gates**

Update `child-usability.md` and `release-checklist.md` only when both supervised columns have no `BLOCKED` result and the Hebrew review has no unresolved copy/layout defect.

Commit:

```bash
git add game/ui game/tests/integration docs/test-results/child-usability.md docs/release-checklist.md
git commit -m "test: pass child usability and Hebrew review gates"
```

If no code changed, omit `game/ui` and `game/tests/integration`.

---

### Task 6: Build, Install, and Tag the Signed 1.0.0 Release Candidate

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/android-build.md`
- Modify: `docs/release-checklist.md`
- Create locally, ignored by Git: `build/animal-heroes-release.apk`
- Create locally, ignored by Git: `build/animal-heroes-release.apk.sha256`

**Interfaces:**
- Consumes: all green automated, device, performance, Hebrew, and usability gates plus an externally stored Android release keystore.
- Produces: a verified signed APK, checksum, installation evidence on both tablets, commit `release: prepare Animal Heroes 1.0.0-rc1`, and annotated tag `v1.0.0-rc1`.

- [ ] **Step 1: Verify the repository and every release gate**

```bash
git status --short --branch
bash scripts/test_all.sh
rg -n 'PENDING|BLOCKED|FAIL' docs/release-checklist.md docs/test-results/sm-t220-performance.md docs/test-results/child-usability.md
```

Expected: a clean branch, full suite exit `0`, and no unresolved release-gate result. Do not proceed on an exception or undocumented waiver.

- [ ] **Step 2: Build and audit the signed release APK**

Configure keystore values outside Git, then run:

```bash
godot --headless --path game --export-release Android build/animal-heroes-release.apk
bash game/tests/device/apk_permissions.sh build/animal-heroes-release.apk
sha256sum build/animal-heroes-release.apk > build/animal-heroes-release.apk.sha256
sha256sum --check build/animal-heroes-release.apk.sha256
```

Expected: export exit `0`, only the four allowed permissions, and checksum verification `OK`.

- [ ] **Step 3: Install the exact release artifact on both tablets**

```bash
source scripts/android_tools.sh
resolve_android_tools
"$ADB_BIN" -s "$HOST_SERIAL" install -r build/animal-heroes-release.apk
"$ADB_BIN" -s "$CLIENT_SERIAL" install -r build/animal-heroes-release.apk
```

Complete one cooperative checkpoint, one competitive match, one rematch, and one return-to-menu flow over automatic discovery. Confirm settings and unlocked progress survive an app restart on both tablets.

- [ ] **Step 4: Finalize release records**

Move the changelog section from `Unreleased` to `1.0.0-rc1` with the actual date. Record the release APK size and SHA-256, both tablet install results, and final smoke result in `docs/release-checklist.md`. Keep the APK and checksum in the ignored `build/` directory or the chosen release distribution system; do not commit the keystore.

- [ ] **Step 5: Commit and tag**

```bash
git add CHANGELOG.md docs/android-build.md docs/release-checklist.md docs/test-results
git commit -m "release: prepare Animal Heroes 1.0.0-rc1"
git tag -a v1.0.0-rc1 -m "Animal Heroes 1.0.0 release candidate"
git status --short --branch
git show --stat --oneline v1.0.0-rc1
```

Expected: clean working tree and the annotated tag pointing at the release-preparation commit. Push the commit and tag only after final review.

---

## Deferred Cleanup After the Release Candidate

- Remove the three clean, merged linked worktrees and their merged branches only after confirming no external task still uses them.
- Investigate ObjectDB/resource cleanup warnings in the headless harness if they obscure new failures; do not delay device validation solely for known exit-time warnings with successful process status.
- Add hosted CI after the local release command is trustworthy; CI should run `bash scripts/test_all.sh` and must not pretend to cover physical-device or supervised-child gates.

