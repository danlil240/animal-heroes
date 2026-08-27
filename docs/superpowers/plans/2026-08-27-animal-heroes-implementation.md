# Animal Heroes LAN Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and release a Hebrew two-player animal platform mini-game that runs offline over LAN on two Samsung Galaxy Tab A7 Lite SM-T220 tablets.

**Architecture:** A Godot 4 project uses a host-authoritative ENet session with UDP broadcast discovery. Gameplay is split into testable core, network, player, world, mode, UI, and audio modules; five phase gates each produce a runnable build before campaign content and polish are added.

**Tech Stack:** Godot 4.x, typed GDScript, ENet, UDP broadcast, Android export templates/SDK, Git, Godot headless tests, ADB physical-device tests.

**Spec:** `docs/superpowers/specs/2026-08-27-animal-heroes-lan-game-design.md`

## Global Constraints

- Target devices: two Samsung Galaxy Tab A7 Lite Wi-Fi tablets, model SM-T220.
- Orientation: landscape only; interface language: Hebrew with right-to-left layout.
- Performance floor: stable 30 FPS in the worst supported two-player scene.
- Network: same-Wi-Fi LAN only; automatic UDP discovery and ENet gameplay; no external service.
- Session authority: host owns enemies, hazards, collectibles, damage, score, checkpoints, timers, and level transitions.
- Safety: original child-friendly art; no realistic weapons, ads, purchases, accounts, chat, or internet matchmaking.
- Controls: left/right, jump, and one context-sensitive action button.
- Tests run headlessly on every task; physical SM-T220 validation begins at Phase 2.
- Use temporary geometric/CC0 assets until the final-art task; never import copyrighted game assets.

## File Structure

```text
game/
  project.godot                         # Godot project and display/render settings
  export_presets.cfg                    # Android debug/release export configuration
  autoload/app_state.gd                 # Scene flow and selected mode
  autoload/save_store.gd                # Versioned settings/progress persistence
  autoload/session.gd                   # Host/client lifecycle facade
  core/game_config.gd                   # Shared constants and version identifiers
  core/checkpoint_state.gd              # Serializable campaign checkpoint
  network/discovery_service.gd          # UDP advertise/listen and compatibility filtering
  network/protocol.gd                   # Bounded message schemas and validation
  network/replicator.gd                 # Inputs, snapshots, interpolation, reconciliation
  network/reconnect_controller.gd       # Pause/retry/resume state machine
  network/session_state.gd              # Allowed session-state transitions
  player/player_body.gd                 # Movement, ability, health, respawn
  player/player_input.gd                # Touch/keyboard input abstraction
  player/player_profile.gd              # Rabbit/fox tuning resource type
  player/player_state.gd                # Serializable player snapshot
  player/rabbit_profile.tres            # Rabbit tuning
  player/fox_profile.tres                # Fox tuning
  world/checkpoint.gd                    # Confirmed checkpoint activation
  world/interactable.gd                 # Switch/pushable interaction contract
  world/enemy.gd                         # Child-friendly enemy state machine
  world/object_pool.gd                   # Reusable projectile/effect pool
  world/partner_indicator.gd             # Off-screen teammate direction
  world/powerup.gd                       # Bubble/star pickup and duration/use limits
  world/robot_boss.gd                    # Deterministic boss phase machine
  modes/coop_mode.gd                     # Campaign win/respawn rules
  modes/star_race_mode.gd                # Race state and grace period
  modes/treasure_dash_mode.gd            # Timed collectible scoring
  modes/bubble_bounce_mode.gd            # Hit score and repeated-hit protection
  modes/match_result.gd                  # Shared result/rematch contract
  ui/main_menu.tscn                      # Hebrew home menu
  ui/touch_controls.tscn                 # Large landscape controls
  ui/connection_overlay.tscn             # Discovery/reconnect feedback
  ui/results_screen.tscn                 # Positive two-player results
  audio/audio_director.gd                # Music/SFX routing and settings
  levels/test_arena.tscn                 # First local/network vertical slice
  levels/sunny_forest.tscn               # Cooperative level 1
  levels/crystal_caves.tscn              # Cooperative level 2
  levels/cloud_factory.tscn              # Cooperative level 3
  levels/robot_boss.tscn                 # Cooperative boss arena
  levels/star_race_arena.tscn            # Race arena
  levels/treasure_dash_arena.tscn        # Collection arena
  levels/bubble_bounce_arena.tscn        # Bubble arena
  tests/support/assertions.gd             # Exit-code-producing assertions
  tests/unit/                             # Pure behavior tests
  tests/integration/                      # Scene and two-process network tests
  tests/device/                           # ADB smoke/performance scripts
scripts/
  test_all.sh                             # Runs every headless test
  run_lan_pair.sh                         # Starts host/client desktop test pair
  build_android.sh                        # Deterministic APK build
  device_smoke.sh                         # Installs and exercises both tablets
```

---

## Phase 1 — Offline Playable Foundation

### Task 1: Godot project and executable test harness

**Files:**
- Create: `game/project.godot`
- Create: `game/core/game_config.gd`
- Create: `game/tests/support/assertions.gd`
- Create: `game/tests/unit/test_project_smoke.gd`
- Create: `scripts/test_all.sh`

**Interfaces:**
- Produces: `GameConfig.PROTOCOL_VERSION`, `GameConfig.CONTENT_VERSION`, and a repeatable headless-test command.

- [ ] **Step 1: Verify the toolchain before writing project files**

Run: `godot --version`

Expected: exit 0 and a version beginning with `4.`. If absent, install a stable Godot 4 editor plus matching Android export templates before continuing.

- [ ] **Step 2: Write the failing smoke test**

```gdscript
extends SceneTree

func _init() -> void:
    var config := load("res://core/game_config.gd")
    if config == null or config.PROTOCOL_VERSION != 1 or config.CONTENT_VERSION != "1.0.0":
        push_error("game_config contract missing")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 3: Run it and verify failure**

Run: `godot --headless --path game -s res://tests/unit/test_project_smoke.gd`

Expected: non-zero exit because the project/config does not yet exist.

- [ ] **Step 4: Add the minimal project and config**

```gdscript
class_name GameConfig
extends RefCounted

const PROTOCOL_VERSION: int = 1
const CONTENT_VERSION: String = "1.0.0"
const TARGET_FPS: int = 30
const MAX_PLAYERS: int = 2
const GAME_PORT: int = 28740
const DISCOVERY_PORT: int = 28741
```

Set `project.godot` to landscape viewport `1340x800`, stretch mode `canvas_items`, Compatibility renderer, physics tick 30, and application name `Animal Heroes`.

- [ ] **Step 5: Add `scripts/test_all.sh`, run, and commit**

```bash
#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
while IFS= read -r test_file; do
  "$GODOT_BIN" --headless --path game -s "res://${test_file#game/}"
done < <(find game/tests -name 'test_*.gd' -type f | sort)
```

Run: `bash scripts/test_all.sh`

Expected: PASS. Commit with:

```bash
git add game/project.godot game/core game/tests scripts/test_all.sh
git commit -m "build: initialize Godot project and test harness"
```

### Task 2: Versioned save data and application state

**Files:**
- Create: `game/autoload/save_store.gd`
- Create: `game/autoload/app_state.gd`
- Create: `game/tests/unit/test_save_store.gd`
- Modify: `game/project.godot`

**Interfaces:**
- Produces: `SaveStore.load_data(path_override := "") -> Dictionary`, `SaveStore.save_data(data, path_override := "") -> Error`, and `AppState.start_mode(mode_id, level_id)`.

- [ ] **Step 1: Write the failing round-trip test**

```gdscript
extends SceneTree

func _init() -> void:
    var store := load("res://autoload/save_store.gd").new()
    var path := "user://test-save.json"
    var data := {"version": 1, "unlocked_levels": ["sunny_forest"], "music": 0.6, "sfx": 0.8, "vibration": false}
    if store.save_data(data, path) != OK or store.load_data(path) != data:
        push_error("save round trip failed")
        quit(1)
        return
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    quit(0)
```

- [ ] **Step 2: Run and verify failure**

Run: `godot --headless --path game -s res://tests/unit/test_save_store.gd`

Expected: FAIL because `save_store.gd` is absent.

- [ ] **Step 3: Implement atomic JSON persistence**

```gdscript
extends Node

const DEFAULT_PATH := "user://animal-heroes-save.json"

func save_data(data: Dictionary, path_override: String = "") -> Error:
    var path := path_override if not path_override.is_empty() else DEFAULT_PATH
    var temp := path + ".tmp"
    var file := FileAccess.open(temp, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(data))
    file.close()
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))

func load_data(path_override: String = "") -> Dictionary:
    var path := path_override if not path_override.is_empty() else DEFAULT_PATH
    if not FileAccess.file_exists(path):
        return {"version": 1, "unlocked_levels": ["sunny_forest"], "music": 0.8, "sfx": 0.8, "vibration": true}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary and parsed.get("version", 0) == 1 else {"version": 1, "unlocked_levels": ["sunny_forest"], "music": 0.8, "sfx": 0.8, "vibration": true}
```

- [ ] **Step 4: Register both autoloads and run tests**

Run: `bash scripts/test_all.sh`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add game/autoload game/project.godot game/tests/unit/test_save_store.gd
git commit -m "feat: add versioned local settings and progress"
```

### Task 3: Player movement, profiles, health, and respawn

**Files:**
- Create: `game/player/player_profile.gd`
- Create: `game/player/player_state.gd`
- Create: `game/player/player_input.gd`
- Create: `game/player/player_body.gd`
- Create: `game/player/rabbit_profile.tres`
- Create: `game/player/fox_profile.tres`
- Create: `game/tests/unit/test_player_rules.gd`
- Create: `game/tests/integration/test_player_scene.gd`

**Interfaces:**
- Produces: `PlayerBody.apply_input(frame: PlayerInput.InputFrame)`, `take_hit(source_peer_id)`, `respawn(at_position)`, and `snapshot() -> PlayerState`.

- [ ] **Step 1: Write failing rule tests for both heroes**

```gdscript
extends SceneTree

func _init() -> void:
    var rabbit = load("res://player/rabbit_profile.tres")
    var fox = load("res://player/fox_profile.tres")
    if rabbit.move_speed <= fox.move_speed or rabbit.jump_speed <= fox.jump_speed or fox.max_hearts != rabbit.max_hearts + 1:
        push_error("hero profile contract failed")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Verify failure**

Run: `godot --headless --path game -s res://tests/unit/test_player_rules.gd`

Expected: FAIL because the resources do not exist.

- [ ] **Step 3: Implement typed profile/input/state contracts**

```gdscript
class_name PlayerProfile
extends Resource

@export var move_speed: float = 220.0
@export var jump_speed: float = 420.0
@export var max_hearts: int = 3
@export var can_push_heavy: bool = false
```

Set rabbit to speed `240`, jump `440`, hearts `3`; set fox to speed `220`, jump `410`, hearts `4`, and `can_push_heavy = true`. `PlayerBody` uses `move_and_slide()`, gravity, coyote time `0.10 s`, jump buffer `0.12 s`, a `0.75 s` damage cooldown, and checkpoint respawn.

- [ ] **Step 4: Add a physics test scene and verify movement/respawn**

Run: `godot --headless --path game -s res://tests/integration/test_player_scene.gd`

Expected: rabbit moves farther than fox over equal input, both land after jumping, damage cooldown blocks a second immediate hit, and respawn restores hearts/position.

- [ ] **Step 5: Run all tests and commit**

```bash
bash scripts/test_all.sh
git add game/player game/tests
git commit -m "feat: add rabbit and fox movement rules"
```

### Task 4: Hebrew menu, tutorial, and touch controls

**Files:**
- Create: `game/ui/main_menu.tscn`
- Create: `game/ui/main_menu.gd`
- Create: `game/ui/touch_controls.tscn`
- Create: `game/ui/touch_controls.gd`
- Create: `game/ui/how_to_play.tscn`
- Create: `game/tests/integration/test_hebrew_ui.gd`

**Interfaces:**
- Consumes: `AppState.start_mode(mode_id, level_id)`.
- Produces: `TouchControls.input_frame() -> PlayerInput.InputFrame` and signals `create_game`, `join_game`, `open_competition`.

- [ ] **Step 1: Write a failing UI contract test**

```gdscript
extends SceneTree

func _init() -> void:
    var menu := load("res://ui/main_menu.tscn").instantiate()
    get_root().add_child(menu)
    var labels := [menu.get_node("Margin/VBox/Coop").text, menu.get_node("Margin/VBox/Competition").text, menu.get_node("Margin/VBox/HowTo").text, menu.get_node("Margin/VBox/Settings").text]
    if labels != ["משחק משותף", "תחרות", "איך משחקים", "הגדרות"]:
        push_error("Hebrew menu contract failed")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Verify the missing-scene failure**

Run: `godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd`

Expected: FAIL loading `main_menu.tscn`.

- [ ] **Step 3: Build the RTL menu and 96-dp minimum touch targets**

Set every Hebrew container to RTL layout direction. `touch_controls.gd` tracks simultaneous pointers by index so moving, jumping, and acting work together; keyboard mappings remain available for desktop testing.

- [ ] **Step 4: Run UI tests at 1340x800 and 1024x600**

Run: `godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd`

Expected: PASS with no clipped labels and all touch rectangles at least 96 logical pixels on their shortest edge.

- [ ] **Step 5: Commit**

```bash
git add game/ui game/tests/integration/test_hebrew_ui.gd
git commit -m "feat: add Hebrew menus and touch controls"
```

### Task 5: Offline two-player test arena

**Files:**
- Create: `game/levels/test_arena.tscn`
- Create: `game/world/partner_indicator.gd`
- Create: `game/tests/integration/test_local_arena.gd`
- Modify: `game/project.godot`

**Interfaces:**
- Consumes: `PlayerBody` and `TouchControls`.
- Produces: runnable offline arena with rabbit/fox spawn markers and independent cameras.

- [ ] **Step 1: Write a failing scene contract test**

```gdscript
extends SceneTree

func _init() -> void:
    var arena := load("res://levels/test_arena.tscn").instantiate()
    get_root().add_child(arena)
    var required := ["RabbitSpawn", "FoxSpawn", "Ground", "Checkpoint", "Collectibles"]
    for node_name in required:
        if arena.get_node_or_null(node_name) == null:
            push_error("missing arena node: " + node_name)
            quit(1)
            return
    quit(0)
```

- [ ] **Step 2: Run and verify failure**

Run: `godot --headless --path game -s res://tests/integration/test_local_arena.gd`

Expected: FAIL because the arena is absent.

- [ ] **Step 3: Build the arena with geometric temporary art**

Create one screen of safe ground, three platforms, ten stars, one fall-respawn zone, and a checkpoint. Each camera follows its local hero; `partner_indicator.gd` clamps an arrow to the viewport edge toward the remote hero.

- [ ] **Step 4: Run tests and a 10-minute desktop play smoke**

Run: `bash scripts/test_all.sh && godot --path game res://levels/test_arena.tscn`

Expected: no physics errors, both characters reach every platform, and respawn never exceeds two seconds.

- [ ] **Step 5: Commit Phase 1 gate**

```bash
git add game
git commit -m "feat: complete offline playable foundation"
```

## Phase 2 — Robust LAN Vertical Slice

### Task 6: Protocol and automatic UDP discovery

**Files:**
- Create: `game/network/protocol.gd`
- Create: `game/network/discovery_service.gd`
- Create: `game/tests/unit/test_protocol.gd`
- Create: `game/tests/integration/test_discovery.gd`

**Interfaces:**
- Produces: `Protocol.encode_discovery(session_id, state) -> PackedByteArray`, `Protocol.decode_discovery(packet) -> Dictionary`, `DiscoveryService.host()`, `listen()`, `stop()`, and signal `host_found(info)`.

- [ ] **Step 1: Write failing encode/validation tests**

```gdscript
extends SceneTree

func _init() -> void:
    var protocol = load("res://network/protocol.gd")
    var packet: PackedByteArray = protocol.encode_discovery("abc123", "lobby")
    var decoded: Dictionary = protocol.decode_discovery(packet)
    if decoded.get("protocol") != 1 or decoded.get("content") != "1.0.0" or decoded.get("session_id") != "abc123":
        push_error("discovery round trip failed")
        quit(1)
        return
    if not protocol.decode_discovery(PackedByteArray([1, 2, 3])).is_empty():
        push_error("malformed packet accepted")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Verify failure, then implement bounded JSON packets**

Reject packets over 512 bytes, missing fields, incompatible versions, invalid IPv4/port values, and session IDs outside `[A-Za-z0-9_-]{6,32}`. Broadcast host advertisements every 750 ms and expire discovered hosts after 2.5 seconds.

- [ ] **Step 3: Run unit and two-process discovery tests**

Run: `bash scripts/test_all.sh`

Expected: compatible host found within 3 seconds; malformed and mismatched advertisements ignored.

- [ ] **Step 4: Add Android permissions**

Enable `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, and multicast capability in the Android export preset; do not request location, contacts, storage, microphone, or camera.

- [ ] **Step 5: Commit**

```bash
git add game/network game/tests game/export_presets.cfg
git commit -m "feat: add compatible LAN host discovery"
```

### Task 7: ENet host/client session lifecycle

**Files:**
- Create: `game/autoload/session.gd`
- Create: `game/network/session_state.gd`
- Create: `game/ui/connection_overlay.tscn`
- Create: `game/tests/integration/test_session_pair.gd`
- Create: `scripts/run_lan_pair.sh`
- Modify: `game/project.godot`

**Interfaces:**
- Produces: `Session.create_game() -> Error`, `join_game(host, port) -> Error`, `leave_game()`, signals `state_changed`, `peer_ready`, `session_error`, and states `IDLE/DISCOVERING/CONNECTING/LOBBY/PLAYING/RECONNECTING`.

- [ ] **Step 1: Write a failing lifecycle state test**

```gdscript
extends SceneTree

func _init() -> void:
    var state = load("res://network/session_state.gd")
    if not state.is_valid_transition(state.IDLE, state.DISCOVERING) or state.is_valid_transition(state.PLAYING, state.CONNECTING):
        push_error("session transition contract failed")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Implement the explicit state graph and two-player ENet peer**

Host binds `GameConfig.GAME_PORT` with maximum two peers. Join uses discovered IPv4/port. Each peer sends version and selected character before `LOBBY -> PLAYING`; incompatibility returns to `IDLE` with a Hebrew error.

- [ ] **Step 3: Build the connection overlay**

Map states to `מחפש משחק…`, `מתחבר…`, `מחכים לשחקן נוסף`, and `מתחילים!`; expose the manual IP screen only after discovery timeout.

- [ ] **Step 4: Run a two-process arena smoke**

Run: `bash scripts/run_lan_pair.sh`

Expected: host and client reach `PLAYING`, each receives a unique peer/character, and a third peer is rejected.

- [ ] **Step 5: Commit**

```bash
git add game scripts/run_lan_pair.sh
git commit -m "feat: connect two-player ENet sessions"
```

### Task 8: Host-authoritative inputs and snapshots

**Files:**
- Create: `game/network/replicator.gd`
- Modify: `game/player/player_state.gd`
- Modify: `game/player/player_body.gd`
- Create: `game/tests/unit/test_snapshot_validation.gd`
- Create: `game/tests/integration/test_replication.gd`

**Interfaces:**
- Produces: `Replicator.submit_input(frame)`, `host_tick(delta)`, `receive_snapshot(snapshot)`, 20 Hz snapshots, 30 Hz input frames, interpolation buffer, and local reconciliation.

- [ ] **Step 1: Write failing sequence/range validation tests**

```gdscript
extends SceneTree

func _init() -> void:
    var protocol = load("res://network/protocol.gd")
    if not protocol.valid_input({"seq": 10, "axis": 1.0, "jump": true, "action": false}):
        push_error("valid input rejected")
        quit(1)
        return
    if protocol.valid_input({"seq": 9, "axis": 8.0, "jump": true, "action": false}):
        push_error("out-of-range input accepted")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Implement input sequencing and bounded snapshots**

Host ignores duplicate/out-of-order frames, clamps axis to `[-1,1]`, rate-limits to 45 frames/second/peer, simulates authority, and publishes position, velocity, hearts, power-up, checkpoint, and last processed sequence.

- [ ] **Step 3: Implement interpolation and reconciliation**

Remote players interpolate 100 ms behind host time. Local prediction replays unacknowledged inputs when error exceeds 8 pixels; corrections over 96 pixels snap at checkpoint/respawn only.

- [ ] **Step 4: Test with 120 ms latency and 5% packet loss**

Run: `godot --headless --path game -s res://tests/integration/test_replication.gd -- --latency-ms=120 --loss=0.05`

Expected: both peers finish within 12 pixels of host position, no duplicate score/damage event, and control remains responsive.

- [ ] **Step 5: Commit**

```bash
git add game/network game/player game/tests
git commit -m "feat: synchronize host-authoritative players"
```

### Task 9: Pause, reconnect, and confirmed checkpoints

**Files:**
- Create: `game/core/checkpoint_state.gd`
- Create: `game/network/reconnect_controller.gd`
- Create: `game/world/checkpoint.gd`
- Modify: `game/autoload/session.gd`
- Modify: `game/autoload/save_store.gd`
- Create: `game/tests/unit/test_reconnect_state.gd`
- Create: `game/tests/integration/test_reconnect_pair.gd`

**Interfaces:**
- Produces: `ReconnectController.connection_lost()`, `tick(delta)`, `restore(snapshot)`, `CheckpointState.to_dict()/from_dict()`, and a 15-second retry window.

- [ ] **Step 1: Write failing reconnect state tests**

```gdscript
extends SceneTree

func _init() -> void:
    var controller := load("res://network/reconnect_controller.gd").new()
    controller.connection_lost("session42")
    controller.tick(14.9)
    if controller.state != controller.RETRYING:
        push_error("retry ended early")
        quit(1)
        return
    controller.tick(0.2)
    if controller.state != controller.FAILED:
        push_error("retry timeout failed")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Implement synchronized pause and resume handshake**

Freeze gameplay authority after 1.5 seconds without valid traffic. Retry the known host every second for 15 seconds. After reconnect, host sends a full snapshot; both peers acknowledge readiness before a three-count resume.

- [ ] **Step 3: Mirror confirmed checkpoint data on both peers**

Persist level ID, checkpoint ID, unlocked levels, and hero state only after host confirmation. On host termination or retry timeout, both return to the menu with the confirmed checkpoint intact.

- [ ] **Step 4: Run interruption, host-kill, and sleep/wake simulations**

Run: `godot --headless --path game -s res://tests/integration/test_reconnect_pair.gd`

Expected: a five-second outage resumes; a 16-second outage exits safely; killing host never corrupts the save.

- [ ] **Step 5: Commit Phase 2 gate**

```bash
git add game
git commit -m "feat: recover LAN sessions from connection loss"
```

## Phase 3 — Cooperative Campaign

### Task 10: Shared world mechanics

**Files:**
- Create: `game/world/interactable.gd`
- Create: `game/world/enemy.gd`
- Create: `game/world/object_pool.gd`
- Create: `game/world/powerup.gd`
- Create: `game/world/test_bubble.tscn`
- Create: `game/modes/coop_mode.gd`
- Create: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Produces: `Interactable.try_activate(player)`, `Enemy.host_step(delta)`, `ObjectPool.acquire()/release(node)`, `Powerup.apply_to(player)`, and `CoopMode.confirm_checkpoint(id)`.

- [ ] **Step 1: Write failing tests for pooling, stomp, and power-up expiry**

```gdscript
extends SceneTree

func _init() -> void:
    var pool := load("res://world/object_pool.gd").new()
    pool.configure(preload("res://world/test_bubble.tscn"), 8)
    var first: Node = pool.acquire()
    pool.release(first)
    if pool.acquire() != first:
        push_error("pool did not reuse object")
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Implement host-only world mutations**

Only host spawns/releases pooled objects, changes enemy state, awards collectibles, applies damage, and activates checkpoints. Clients request actions using peer ID and input sequence; host validates proximity and cooldown.

- [ ] **Step 3: Implement rabbit/fox cooperative interactions**

Both heroes activate ordinary switches. Fox alone pushes nodes tagged `heavy`; rabbit's higher jump reaches optional bonus routes. Required progress always has a recovery route for either player.

- [ ] **Step 4: Run world-rule and replication tests**

Run: `bash scripts/test_all.sh`

Expected: no duplicate pickup/hit, pool size remains bounded, and invalid remote activation is rejected.

- [ ] **Step 5: Commit**

```bash
git add game/world game/modes/coop_mode.gd game/tests
git commit -m "feat: add authoritative cooperative world mechanics"
```

### Task 11: Sunny Forest level

**Files:**
- Create: `game/levels/sunny_forest.tscn`
- Create: `game/levels/sunny_forest.gd`
- Create: `game/tests/integration/test_sunny_forest.gd`

**Interfaces:**
- Produces: 8–12 minute tutorial level with four checkpoints, collectibles, two enemy types, bubble power-up, and exit requiring both players.

- [ ] **Step 1: Write a failing level contract test**

```gdscript
extends SceneTree

func _init() -> void:
    var level := load("res://levels/sunny_forest.tscn").instantiate()
    get_root().add_child(level)
    var valid := level.get_tree().get_nodes_in_group("player_spawn").size() == 2 \
        and level.get_tree().get_nodes_in_group("checkpoint").size() >= 4 \
        and level.get_tree().get_nodes_in_group("collectible").size() >= 10 \
        and level.get_tree().get_nodes_in_group("bubble_powerup").size() >= 1 \
        and level.get_node("Exit").required_players == 2
    quit(0 if valid else 1)
```

- [ ] **Step 2: Verify failure**

Run: `godot --headless --path game -s res://tests/integration/test_sunny_forest.gd`

Expected: FAIL because the scene is absent.

- [ ] **Step 3: Build four teach-test-remix sections**

Section order: movement/jump, stomp/collect, bubble/action, partner switch/exit. Maximum mandatory fall is 160 logical pixels; every fall zone respawns within two seconds.

- [ ] **Step 4: Run automated traversal and two-player playtest**

Expected: scripted agents reach every checkpoint; two humans finish without developer intervention; checkpoint state matches on both peers.

- [ ] **Step 5: Commit**

```bash
git add game/levels/sunny_forest* game/tests/integration/test_sunny_forest.gd
git commit -m "feat: add Sunny Forest cooperative level"
```

### Task 12: Crystal Caves level

**Files:**
- Create: `game/levels/crystal_caves.tscn`
- Create: `game/levels/crystal_caves.gd`
- Create: `game/tests/integration/test_crystal_caves.gd`

**Interfaces:**
- Produces: 8–12 minute level with moving platforms, paired switches, doors, fox heavy push, and reunification routes.

- [ ] **Step 1: Write the level contract test**

```gdscript
extends SceneTree

func _init() -> void:
    var level := load("res://levels/crystal_caves.tscn").instantiate()
    get_root().add_child(level)
    var valid := level.get_tree().get_nodes_in_group("checkpoint").size() >= 4 \
        and level.get_tree().get_nodes_in_group("moving_platform").size() >= 2 \
        and level.get_tree().get_nodes_in_group("switch_door_pair").size() >= 2 \
        and level.get_tree().get_nodes_in_group("heavy_pushable").size() >= 1 \
        and level.get_tree().get_nodes_in_group("reunion_route").size() >= 2
    quit(0 if valid else 1)
```

- [ ] **Step 2: Verify missing-scene failure**

Run: `godot --headless --path game -s res://tests/integration/test_crystal_caves.gd`

- [ ] **Step 3: Build the scene with host-owned platform phase**

Moving platform phase derives from host tick time and replicates phase/velocity; clients never simulate an independent clock. Doors validate switch occupancy on host.

- [ ] **Step 4: Test at 120 ms latency and disconnect at every gate**

Expected: platforms remain aligned, neither player is trapped, and reconnection restores switch/door state.

- [ ] **Step 5: Commit**

```bash
git add game/levels/crystal_caves* game/tests/integration/test_crystal_caves.gd
git commit -m "feat: add Crystal Caves cooperative level"
```

### Task 13: Cloud Factory level

**Files:**
- Create: `game/levels/cloud_factory.tscn`
- Create: `game/levels/cloud_factory.gd`
- Create: `game/tests/integration/test_cloud_factory.gd`

**Interfaces:**
- Produces: 8–12 minute level with fans, conveyors, combined mechanics, four checkpoints, boss entrance, and integer properties `enemy_budget`, `projectile_budget`, `particle_budget`.

- [ ] **Step 1: Write the failing contract/performance test**

```gdscript
extends SceneTree

func _init() -> void:
    var level := load("res://levels/cloud_factory.tscn").instantiate()
    get_root().add_child(level)
    var valid := level.get_tree().get_nodes_in_group("checkpoint").size() >= 4 \
        and level.get_tree().get_nodes_in_group("fan_zone").size() >= 3 \
        and level.get_tree().get_nodes_in_group("conveyor").size() >= 3 \
        and level.get_node_or_null("BossEntrance") != null \
        and level.enemy_budget <= 12 and level.projectile_budget <= 24 and level.particle_budget <= 80
    quit(0 if valid else 1)
```

- [ ] **Step 2: Verify failure, then build mechanics from host-authored forces**

Fan/conveyor forces are deterministic values in the host physics tick. Clients display effects but accept authoritative player motion.

- [ ] **Step 3: Add combined mechanic sequences with safe restart ledges**

Each challenge has a visible landing target and respawn ledge; no checkpoint-to-checkpoint segment exceeds 90 seconds for the slower hero.

- [ ] **Step 4: Run worst-scene performance capture**

Expected: desktop headless test passes entity budgets; physical performance is formally gated in Task 22.

- [ ] **Step 5: Commit**

```bash
git add game/levels/cloud_factory* game/tests/integration/test_cloud_factory.gd
git commit -m "feat: add Cloud Factory cooperative level"
```

### Task 14: Comical robot boss and campaign completion

**Files:**
- Create: `game/levels/robot_boss.tscn`
- Create: `game/world/robot_boss.gd`
- Create: `game/tests/unit/test_boss_phases.gd`
- Modify: `game/modes/coop_mode.gd`

**Interfaces:**
- Produces: boss phases `INTRO/AVOID/SWITCHES/WEAK_POINT/DEFEATED`, checkpointed retries, and campaign unlock persistence.

- [ ] **Step 1: Write a failing deterministic phase test**

```gdscript
extends SceneTree

func _init() -> void:
    var boss := load("res://world/robot_boss.gd").new()
    boss.begin(true)
    for cycle in 3:
        boss.activate_switch(1)
        boss.activate_switch(2)
        boss.hit_weak_point(1)
        boss.hit_weak_point(2)
    if boss.phase != boss.DEFEATED or boss.defeat_emissions != 1:
        quit(1)
        return
    quit(0)
```

- [ ] **Step 2: Implement the phase machine**

Telegraph every attack for at least 0.8 seconds; cap a phase at 45 seconds; after failure restore players/boss to the current boss checkpoint in two seconds.

- [ ] **Step 3: Add synchronized victory and save update**

Host sends `campaign_completed`; both peers persist all three unlocked levels and the completion flag before opening results.

- [ ] **Step 4: Run the full 30–45 minute campaign twice**

Expected: one clean run and one run with a reconnect in each level; no divergent checkpoint, duplicate boss hit, or save mismatch.

- [ ] **Step 5: Commit Phase 3 gate**

```bash
git add game
git commit -m "feat: complete cooperative campaign and boss"
```

## Phase 4 — Competitive Modes

### Task 15: Shared match contract and Star Race

**Files:**
- Create: `game/modes/match_result.gd`
- Create: `game/modes/star_race_mode.gd`
- Create: `game/levels/star_race_arena.tscn`
- Create: `game/tests/unit/test_star_race.gd`

**Interfaces:**
- Produces: `MatchResult(winner_peer_id, scores, reason)` with `finish_order: Array[int]`, `StarRaceMode.start()`, `finish(peer_id, host_tick)`, `finalize() -> MatchResult`, and a 15-second second-finisher grace period.

- [ ] **Step 1: Write failing finish-order/tie tests**

```gdscript
extends SceneTree

func _init() -> void:
    var mode := load("res://modes/star_race_mode.gd").new()
    mode.start()
    mode.finish(2, 900)
    mode.finish(1, 901)
    mode.finish(2, 902)
    var result = mode.finalize()
    quit(0 if result.winner_peer_id == 2 and result.finish_order == [2, 1] else 1)
```

- [ ] **Step 2: Implement host-only race state**

Use four checkpoints per route and no shortcut that skips an ordered checkpoint. Respawn uses the player's most recent race checkpoint.

- [ ] **Step 3: Build a 2–4 minute arena and run two-peer tests**

Expected: both heroes have routes within 5% median completion time over five scripted runs.

- [ ] **Step 4: Run all tests**

Run: `bash scripts/test_all.sh`

- [ ] **Step 5: Commit**

```bash
git add game/modes game/levels/star_race_arena.tscn game/tests
git commit -m "feat: add two-player Star Race"
```

### Task 16: Treasure Dash

**Files:**
- Create: `game/modes/treasure_dash_mode.gd`
- Create: `game/levels/treasure_dash_arena.tscn`
- Create: `game/tests/unit/test_treasure_dash.gd`

**Interfaces:**
- Produces: `TreasureDashMode.start(duration)`, `collect(peer_id, collectible_id, type)`, `tick(delta)`, `score(peer_id) -> int`, a 180-second host timer, values fruit `1`/gem `3`/star `5`, deterministic respawn points, and final `MatchResult`.

- [ ] **Step 1: Write failing scoring/timer tests**

```gdscript
extends SceneTree

func _init() -> void:
    var mode := load("res://modes/treasure_dash_mode.gd").new()
    mode.start(180.0)
    mode.collect(1, "fruit-1", "fruit")
    mode.collect(1, "fruit-1", "fruit")
    mode.collect(2, "star-1", "star")
    mode.tick(180.0)
    mode.collect(1, "gem-after-time", "gem")
    quit(0 if mode.score(1) == 1 and mode.score(2) == 5 else 1)
```

- [ ] **Step 2: Implement bounded host-owned collectible spawning**

Keep at most 24 active items; choose spawn point from a seeded shuffled bag; exclude points within 160 pixels of either player.

- [ ] **Step 3: Build arena and run fairness simulation**

Expected: neither spawn side produces more than 10% score advantage across 100 seeded scripted matches.

- [ ] **Step 4: Run all tests**

Run: `bash scripts/test_all.sh`

- [ ] **Step 5: Commit**

```bash
git add game/modes/treasure_dash_mode.gd game/levels/treasure_dash_arena.tscn game/tests
git commit -m "feat: add Treasure Dash competition"
```

### Task 17: Bubble Bounce

**Files:**
- Create: `game/modes/bubble_bounce_mode.gd`
- Create: `game/levels/bubble_bounce_arena.tscn`
- Create: `game/tests/unit/test_bubble_bounce.gd`

**Interfaces:**
- Produces: `BubbleBounceMode.start(duration)`, `register_hit(owner_id, target_id, projectile_id, host_time)`, `score(peer_id) -> int`, a 180-second match, one point per valid hit, 1.25-second repeated-hit protection, bounded knockback, and immediate continued control.

- [ ] **Step 1: Write failing hit-protection tests**

```gdscript
extends SceneTree

func _init() -> void:
    var mode := load("res://modes/bubble_bounce_mode.gd").new()
    mode.start(180.0)
    mode.register_hit(1, 2, "bubble-1", 0.0)
    mode.register_hit(1, 2, "bubble-2", 0.5)
    mode.register_hit(1, 1, "bubble-3", 2.0)
    mode.register_hit(1, 2, "bubble-4", 2.0)
    quit(0 if mode.score(1) == 2 else 1)
```

- [ ] **Step 2: Implement host validation**

Validate projectile owner, active projectile ID, target overlap, protection deadline, and match state. Clamp horizontal knockback to 260 and vertical knockback to 180 logical pixels/second.

- [ ] **Step 3: Build an arena without elimination pits**

Use soft walls, three platform heights, bubble refill zones, and instant safe respawn only for accidental out-of-bounds.

- [ ] **Step 4: Run 20 repeated matches with packet loss**

Expected: scores match on both peers; no control lock lasts beyond one physics frame.

- [ ] **Step 5: Commit**

```bash
git add game/modes/bubble_bounce_mode.gd game/levels/bubble_bounce_arena.tscn game/tests
git commit -m "feat: add Bubble Bounce competition"
```

### Task 18: Positive results and rematch flow

**Files:**
- Create: `game/ui/results_screen.tscn`
- Create: `game/ui/results_screen.gd`
- Create: `game/tests/integration/test_results_flow.gd`
- Modify: `game/ui/main_menu.gd`

**Interfaces:**
- Consumes: `MatchResult`.
- Produces: `ResultsScreen.show_result(result)`, `choose_rematch(peer_id)`, `rematch_ready() -> bool`, `displayed_scores: Dictionary`, winner ribbon/crown, positive animation for both players, synchronized rematch, and return-to-mode menu.

- [ ] **Step 1: Write a failing two-peer rematch test**

```gdscript
extends SceneTree

func _init() -> void:
    var screen := load("res://ui/results_screen.tscn").instantiate()
    get_root().add_child(screen)
    screen.show_result({"winner_peer_id": 1, "scores": {1: 5, 2: 3}})
    screen.choose_rematch(1)
    if screen.rematch_ready():
        quit(1)
        return
    screen.choose_rematch(2)
    quit(0 if screen.rematch_ready() and screen.displayed_scores == {1: 5, 2: 3} else 1)
```

- [ ] **Step 2: Implement the Hebrew results UI**

Use `כל הכבוד!`, player icons, large score glyphs, `שוב!`, and `בחירת משחק`; avoid loser labels or negative sounds.

- [ ] **Step 3: Test all three modes through five rematches**

Expected: no stale timer, score, projectile, collectible, or ready flag survives a reset.

- [ ] **Step 4: Run full suite**

Run: `bash scripts/test_all.sh`

- [ ] **Step 5: Commit Phase 4 gate**

```bash
git add game
git commit -m "feat: complete friendly competitive modes"
```

## Phase 5 — Art, Audio, Android, and Release

### Task 19: Original Style-A art and animation integration

**Files:**
- Create: `game/assets/characters/rabbit.png`
- Create: `game/assets/characters/fox.png`
- Create: `game/assets/worlds/sunny_forest.png`
- Create: `game/assets/worlds/crystal_caves.png`
- Create: `game/assets/worlds/cloud_factory.png`
- Create: `game/assets/worlds/competition.png`
- Create: `game/assets/ui/game_ui.png`
- Create: `game/assets/effects/game_effects.png`
- Create: `game/assets/ATTRIBUTION.md`
- Modify: `game/player/player_body.gd`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/levels/sunny_forest.tscn`
- Modify: `game/levels/crystal_caves.tscn`
- Modify: `game/levels/cloud_factory.tscn`
- Modify: `game/levels/robot_boss.tscn`
- Modify: `game/levels/star_race_arena.tscn`
- Modify: `game/levels/treasure_dash_arena.tscn`
- Modify: `game/levels/bubble_bounce_arena.tscn`
- Modify: `game/ui/main_menu.tscn`
- Modify: `game/ui/touch_controls.tscn`
- Modify: `game/ui/results_screen.tscn`

**Interfaces:**
- Produces: original atlased sprites with fixed animation names `idle`, `run`, `jump`, `fall`, `action`, `hurt`, `celebrate`.

- [ ] **Step 1: Add an asset contract test before replacing placeholders**

Load every character `SpriteFrames`; assert required animations exist, no atlas exceeds 2048x2048, textures use VRAM compression for Android, and total decoded texture budget for a level stays below 96 MiB.

- [ ] **Step 2: Create and import original assets**

Use the approved saturated 1990s-cartoon direction, thick readable silhouettes, rabbit/fox color separation, harmless bubbles/stars, and four distinct world palettes. Record source/license for every non-original asset in `ATTRIBUTION.md`.

- [ ] **Step 3: Replace temporary art without changing collision shapes**

Keep physics geometry independent of visible sprites; align animation origin at the feet; constrain particles to the Phase 3 budgets.

- [ ] **Step 4: Run screenshot and asset-budget tests**

Expected: characters remain distinguishable at 75% render scale and no scene exceeds texture/entity budgets.

- [ ] **Step 5: Commit**

```bash
git add game/assets game/player game/levels game/ui
git commit -m "art: integrate original Animal Heroes visual style"
```

### Task 20: Audio, settings, accessibility, and Hebrew review

**Files:**
- Create: `game/audio/audio_director.gd`
- Create: `game/assets/audio/sunny_forest.ogg`
- Create: `game/assets/audio/crystal_caves.ogg`
- Create: `game/assets/audio/cloud_factory.ogg`
- Create: `game/assets/audio/competition.ogg`
- Create: `game/assets/audio/sfx_ui.wav`
- Create: `game/assets/audio/sfx_gameplay.wav`
- Modify: `game/autoload/save_store.gd`
- Modify: `game/player/player_body.gd`
- Modify: `game/world/checkpoint.gd`
- Modify: `game/world/powerup.gd`
- Modify: `game/network/reconnect_controller.gd`
- Modify: `game/ui/main_menu.gd`
- Modify: `game/ui/results_screen.gd`
- Create: `game/tests/integration/test_settings.gd`

**Interfaces:**
- Produces: independent `Music`/`SFX` buses, persisted volume, optional vibration, distinct visual equivalents for audio-only events.

- [ ] **Step 1: Write failing persistence/bus tests**

Set music `0.25`, SFX `0.75`, vibration false; reload and assert values/bus dB conversion persist. Assert every checkpoint, damage, objective, and connection signal triggers a visual event.

- [ ] **Step 2: Implement audio routing and voice limits**

Limit simultaneous SFX voices to 12, projectiles to four audible voices, and crossfade world music over 0.5 seconds. Normalize assets to avoid clipping.

- [ ] **Step 3: Complete native Hebrew review**

Review every visible string for age-appropriate Hebrew, RTL punctuation, truncation, and consistency; keep normal child flow icon-led.

- [ ] **Step 4: Run settings/relaunch tests**

Expected: settings survive process restart; muted play remains fully understandable visually.

- [ ] **Step 5: Commit**

```bash
git add game/audio game/assets/audio game/autoload game/tests game/ui game/levels
git commit -m "feat: add accessible audio and persistent settings"
```

### Task 21: Android export and deterministic APK build

**Files:**
- Create: `scripts/build_android.sh`
- Modify: `game/export_presets.cfg`
- Create: `docs/android-build.md`
- Create: `game/tests/device/apk_permissions.sh`

**Interfaces:**
- Produces: `build/animal-heroes-debug.apk` and signed `build/animal-heroes-release.apk` from the same content version.

- [ ] **Step 1: Verify Android prerequisites**

Run: `godot --headless --path game --export-debug Android build/animal-heroes-debug.apk`

Expected before configuration: a clear export-template/SDK/keystore failure; document the detected Godot, Java, SDK, build-tools, and ADB versions in `docs/android-build.md`.

- [ ] **Step 2: Configure package and permissions**

Use package ID `com.danlil240.animalheroes`, landscape orientation, minimum Android API 24, arm64-v8a, and only the LAN/network permissions listed in Task 6.

- [ ] **Step 3: Add deterministic build script**

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
godot --headless --path game --export-debug Android build/animal-heroes-debug.apk
sha256sum build/animal-heroes-debug.apk > build/animal-heroes-debug.apk.sha256
```

Create `apk_permissions.sh` to fail if `aapt dump permissions` includes camera, microphone, contacts, phone, location, SMS, or broad storage permissions:

```bash
#!/usr/bin/env bash
set -euo pipefail
APK="$1"
PERMISSIONS="$(aapt dump permissions "$APK")"
if grep -Eq 'CAMERA|RECORD_AUDIO|READ_CONTACTS|WRITE_CONTACTS|READ_PHONE|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|READ_SMS|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE' <<<"$PERMISSIONS"; then
  printf '%s\n' "$PERMISSIONS"
  exit 1
fi
```

- [ ] **Step 4: Audit and install the debug APK**

Run: `bash scripts/build_android.sh && bash game/tests/device/apk_permissions.sh build/animal-heroes-debug.apk && adb install -r build/animal-heroes-debug.apk`

Expected: APK installs, opens landscape, and permission audit finds no sensitive permission.

- [ ] **Step 5: Commit**

```bash
git add scripts/build_android.sh game/export_presets.cfg game/tests/device docs/android-build.md
git commit -m "build: export installable Android APK"
```

### Task 22: SM-T220 performance and LAN endurance gate

**Files:**
- Create: `scripts/device_smoke.sh`
- Create: `game/tests/device/performance_check.gd`
- Create: `docs/test-results/sm-t220-performance.md`
- Modify: `game/project.godot`
- Modify: `game/levels/cloud_factory.tscn`
- Modify: `game/world/enemy.gd`
- Modify: `game/world/object_pool.gd`

**Interfaces:**
- Produces: recorded 30 FPS minimum evidence, memory/thermal observations, and repeatable dual-device LAN smoke.

- [ ] **Step 1: Identify both tablets explicitly**

Run: `adb devices -l`

Expected: two authorized SM-T220 serials. Pass them explicitly as `HOST_SERIAL` and `CLIENT_SERIAL`; never rely on implicit device selection.

- [ ] **Step 2: Run a failing baseline capture**

Install the APK, clear logs, host/join automatically, traverse the Cloud Factory stress area for ten minutes, and record frame-time percentiles, memory, thermal status, battery change, reconnect count, and Android errors.

- [ ] **Step 3: Optimize only measured bottlenecks**

In order: reduce particles/overdraw, pool remaining allocations, reduce active enemy/projectile caps, compress oversized textures/audio, then lower render scale. Never alter physics/network ticks to hide rendering cost.

- [ ] **Step 4: Pass the endurance matrix**

Complete one 45-minute campaign, 20 rounds per competitive arena, 25 create/join cycles, five 5-second Wi-Fi losses, one 16-second loss, host/client sleep-wake, and host termination. Required: no crash/corrupt save/desync and no gameplay interval below 30 FPS for more than one second.

- [ ] **Step 5: Commit measured fixes and evidence**

```bash
git add game scripts/device_smoke.sh docs/test-results/sm-t220-performance.md
git commit -m "perf: pass dual SM-T220 endurance gate"
```

### Task 23: Child usability, release candidate, and handoff

**Files:**
- Create: `docs/test-results/child-usability.md`
- Create: `docs/release-checklist.md`
- Create: `CHANGELOG.md`
- Modify: `game/ui/main_menu.tscn`
- Modify: `game/ui/touch_controls.tscn`
- Modify: `game/ui/how_to_play.tscn`
- Modify: `game/ui/connection_overlay.tscn`

**Interfaces:**
- Produces: signed release APK, SHA-256 checksum, install instructions, and completed acceptance checklist.

- [ ] **Step 1: Run supervised usability sessions**

Observe each child creating/joining with minimal adult help, completing Sunny Forest, playing each competition, recovering from a fall, and choosing rematch. Record only task outcomes and interface issues; do not collect personal data, audio, or video.

- [ ] **Step 2: Fix observed blockers with regression tests**

For each blocker, add a focused UI/input test first, reproduce it, apply the smallest change, and rerun the full automated/device suite. Do not add new game modes or content during release stabilization.

- [ ] **Step 3: Verify every acceptance criterion**

Use a checked table in `docs/release-checklist.md` mapping all nine spec acceptance criteria to an automated result, physical-device result, or supervised usability result.

- [ ] **Step 4: Build and verify release artifacts**

Keep keystore credentials outside Git in the local Godot editor/export environment, then run:

```bash
mkdir -p build
godot --headless --path game --export-release Android build/animal-heroes-release.apk
sha256sum build/animal-heroes-release.apk | tee build/animal-heroes-release.apk.sha256
adb -s "$HOST_SERIAL" install -r build/animal-heroes-release.apk
adb -s "$CLIENT_SERIAL" install -r build/animal-heroes-release.apk
sha256sum --check build/animal-heroes-release.apk.sha256
```

Complete one cooperative checkpoint and one competitive match on the fresh installs.

- [ ] **Step 5: Commit and tag the release candidate**

```bash
git add CHANGELOG.md docs game scripts
git commit -m "release: prepare Animal Heroes 1.0.0"
git tag -a v1.0.0-rc1 -m "Animal Heroes 1.0.0 release candidate"
```

## Phase Gates and Review Order

1. **Phase 1:** Offline arena playable with both hero profiles, Hebrew UI, touch controls, and local saves.
2. **Phase 2:** Two tablets discover, connect, synchronize, pause, and reconnect in the test arena.
3. **Phase 3:** Complete cooperative campaign and boss pass network/checkpoint tests.
4. **Phase 4:** All three competitive modes pass fairness, reset, and rematch tests.
5. **Phase 5:** Original presentation, signed Android build, dual-SM-T220 endurance, and child usability meet all acceptance criteria.

Stop for review at every phase gate. Do not begin the next phase while the current gate has failing tests or unresolved physical-device defects.
