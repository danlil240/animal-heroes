# Sunny Forest Complete Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one polished, network-consistent 8–10 minute Sunny Forest level with context actions, enemies, health recovery, bubbles, teamwork gates, a shared score, a complete finish flow, and Animated Storybook presentation.

**Architecture:** Keep movement locally responsive while the host owns every shared world mutation. Add small rule objects for score, action selection, and ammunition; wrap enemy and projectile rules in scene actors; let `SunnyForest` compose those pieces and let `TwoPlayerLevel` provide a generic idempotent world-event transport. Presentation remains below gameplay nodes and never mutates physics state.

**Tech Stack:** Godot 4.7.2, typed GDScript, Godot ENet RPC, original SVG assets, existing WAV banks, Bash verification scripts, Android debug export.

**Spec:** `docs/superpowers/specs/2026-08-29-sunny-forest-vertical-slice-design.md`

## Global Constraints

- Target players are children aged four to five.
- Keep the existing left, right, jump, and action controls with 128-pixel minimum touch targets.
- Keep `physics/common/physics_ticks_per_second=30` and `TwoPlayerLevel.NET_SYNC_HZ=20.0` unchanged.
- Add no third-party dependencies.
- Keep package ID `org.danlil.animalheroes` unchanged.
- Keep the exact Android permission set: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- Keep the deploy service Python-stdlib-only.
- Do not claim physical 30 FPS, child usability, or two-tablet completion without real operator evidence.
- Preserve user-owned files under `docs/test-results/` and unrelated worktree changes.

---

## File Structure

### New focused gameplay files

- `game/core/team_score.gd` — exact score values plus duplicate-event protection and snapshot restore.
- `game/player/action_resolver.gd` — deterministic nearby-target selection only.
- `game/player/bubble_inventory.gd` — per-peer bounded ammunition.
- `game/world/enemy_actor.gd` — scene collision, host stepping, damage/stomp/bubble transitions around `Enemy` rules.
- `game/world/bubble_projectile.gd` — one pooled, bounded projectile lifecycle.
- `game/world/teamwork_gate.gd` — multi-part completion and one-time scoring state.
- `game/ui/gameplay_hud.gd` and `.tscn` — shared score, both heart rows, ammo, context prompt, score feedback.
- `game/visual/seed_enemy_visual.gd` and `.tscn` — telegraph/hop/defeat presentation.
- `game/visual/magical_tree_visual.gd` and `.tscn` — finish-ready and celebration presentation.
- Original SVGs under `game/art/objects/` and `game/art/environment/sunny_forest/` for the seed, log, pressure flower, bubble flower, magical tree, and additional storybook scenery.

### Existing files with bounded changes

- `game/player/player_body.gd` — spawn protection, knockback, control lock, and explicit action edge access.
- `game/levels/two_player_level.gd` — generic request/event/snapshot transport and host-role access.
- `game/levels/coop_level.gd` — shared score, collected-star IDs, checkpoint snapshot fields.
- `game/levels/sunny_forest.gd` and `.tscn` — objective orchestration and complete four-section scene.
- `game/ui/touch_controls.gd` and `.tscn` — context icon and bubble-ammo display hook without moving controls.
- `game/audio/audio_director.gd` — named bounded gameplay cue methods.
- `game/visual/hero_visual.gd` and `.tscn` — readable action, damage, respawn, and celebration poses.
- `game/autoload/session.gd` — read-only `is_host()` and authoritative-snapshot accessors.

### Tests

- Extend `game/tests/unit/test_world_rules.gd` for score, resolver, inventory, enemy, projectile, damage, and gate rules.
- Extend `game/tests/integration/test_sunny_forest.gd` for actual section progression and finish payload.
- Add `game/tests/integration/test_sunny_forest_network.gd` for idempotent host validation/application in one process.
- Extend `game/tests/integration/test_visual_target.gd` for HUD, new visual scenes, and presentation/physics separation.
- Extend `scripts/run_lan_pair.sh` with a Sunny Forest scripted-world scenario only if the existing role harness supports scenario selection without weakening its default session test.

---

### Task 1: Shared Score and Bubble Inventory Rules

**Files:**
- Create: `game/core/team_score.gd`
- Create: `game/player/bubble_inventory.gd`
- Modify: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Produces: `TeamScore.award(event_id: String, category: String) -> int`
- Produces: `TeamScore.snapshot() -> Dictionary`
- Produces: `TeamScore.restore(data: Dictionary) -> bool`
- Produces: `BubbleInventory.grant(peer_id: int, amount: int = 5) -> int`
- Produces: `BubbleInventory.consume(peer_id: int) -> bool`
- Produces: `BubbleInventory.remaining(peer_id: int) -> int`
- Produces: `BubbleInventory.snapshot() -> Dictionary`

- [ ] **Step 1: Write failing score and inventory tests**

Add `_test_team_score()` and `_test_bubble_inventory()` to the unit runner:

```gdscript
func _test_team_score() -> void:
	var score = load("res://core/team_score.gd").new()
	if score.award("star-1", "star") != 10:
		_fail("first star must add exactly 10")
	if score.award("star-1", "star") != 0 or score.total != 10:
		_fail("duplicate event ids must not score twice")
	if score.award("enemy-1", "enemy") != 25:
		_fail("enemy must add exactly 25")
	if score.award("gate-1", "teamwork") != 100 or score.total != 135:
		_fail("teamwork must add exactly 100")
	var restored = load("res://core/team_score.gd").new()
	if not restored.restore(score.snapshot()) or restored.total != 135:
		_fail("score snapshot must round trip")

func _test_bubble_inventory() -> void:
	var inventory = load("res://player/bubble_inventory.gd").new()
	if inventory.grant(1) != 5 or inventory.remaining(1) != 5:
		_fail("default bubble flower must grant five shots")
	for index in 5:
		if not inventory.consume(1):
			_fail("granted bubble shot %d must be consumable" % index)
	if inventory.consume(1) or inventory.remaining(1) != 0:
		_fail("empty bubble inventory must reject consumption")
```

- [ ] **Step 2: Run the unit test and verify red**

Run:

```bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
```

Expected: failure because `team_score.gd` and `bubble_inventory.gd` do not exist.

- [ ] **Step 3: Implement minimal typed rules**

`TeamScore` must use the fixed mapping and reject empty/unknown events:

```gdscript
class_name TeamScore
extends RefCounted

const VALUES := {"star": 10, "enemy": 25, "teamwork": 100}

var total: int = 0
var _awarded_ids: Dictionary = {}

func award(event_id: String, category: String) -> int:
	if event_id.is_empty() or _awarded_ids.has(event_id) or not VALUES.has(category):
		return 0
	var points: int = int(VALUES[category])
	_awarded_ids[event_id] = true
	total += points
	return points

func snapshot() -> Dictionary:
	return {"total": total, "awarded_ids": _awarded_ids.keys()}

func restore(data: Dictionary) -> bool:
	var next_total: int = int(data.get("total", -1))
	var ids: Variant = data.get("awarded_ids", null)
	if next_total < 0 or not ids is Array:
		return false
	total = next_total
	_awarded_ids.clear()
	for event_id in ids:
		if String(event_id).is_empty():
			return false
		_awarded_ids[String(event_id)] = true
	return true
```

`BubbleInventory` stores only positive peer IDs and clamps to five:

```gdscript
class_name BubbleInventory
extends RefCounted

const MAX_AMMO := 5
var _ammo: Dictionary = {}

func grant(peer_id: int, amount: int = MAX_AMMO) -> int:
	if peer_id <= 0:
		return 0
	_ammo[peer_id] = mini(MAX_AMMO, int(_ammo.get(peer_id, 0)) + maxi(amount, 0))
	return int(_ammo[peer_id])

func consume(peer_id: int) -> bool:
	var count := remaining(peer_id)
	if count <= 0:
		return false
	_ammo[peer_id] = count - 1
	return true

func remaining(peer_id: int) -> int:
	return int(_ammo.get(peer_id, 0))

func snapshot() -> Dictionary:
	return _ammo.duplicate(true)
```

- [ ] **Step 4: Run the unit test and verify green**

Run the same Godot command. Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/core/team_score.gd game/player/bubble_inventory.gd game/tests/unit/test_world_rules.gd
git commit -m "game: add shared score and bubble inventory rules"
```

---

### Task 2: Deterministic Context Action Resolution

**Files:**
- Create: `game/player/action_resolver.gd`
- Modify: `game/world/interactable.gd`
- Modify: `game/player/player_body.gd`
- Modify: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Consumes: nodes exposing `interaction_id`, `interaction_kind`, `interaction_priority`, `eligible_for(hero)`.
- Produces: `ActionResolver.select(hero: Node2D, candidates: Array, max_distance: float = 96.0) -> Node2D`
- Produces: `PlayerBody.consume_action() -> bool` as one rising-edge event, preserving the existing public signature.

- [ ] **Step 1: Write failing priority, range, tie-break, and edge tests**

```gdscript
func _test_action_resolver() -> void:
	var resolver = load("res://player/action_resolver.gd").new()
	var hero := Node2D.new()
	hero.position = Vector2.ZERO
	root.add_child(hero)
	var bubble := _make_interaction("bubble", "bubble", 10, Vector2(20, 0))
	var gate := _make_interaction("gate", "switch", 100, Vector2(80, 0))
	if resolver.select(hero, [bubble, gate]) != gate:
		_fail("higher priority nearby teamwork target must beat bubble")
	gate.position = Vector2(200, 0)
	if resolver.select(hero, [gate, bubble]) != bubble:
		_fail("out-of-range target must be ignored")
	var first := _make_interaction("a", "switch", 50, Vector2(30, 0))
	var second := _make_interaction("b", "switch", 50, Vector2(-30, 0))
	if resolver.select(hero, [second, first]) != first:
		_fail("equal targets must use stable interaction id order")
```

The helper creates `Interactable` instances and sets exported properties. Extend the existing player test so holding action across two frames yields one `consume_action()` success until released and pressed again.

- [ ] **Step 2: Run the unit tests and verify red**

Expected: missing resolver and missing interaction fields.

- [ ] **Step 3: Implement selection without side effects**

```gdscript
class_name ActionResolver
extends RefCounted

func select(hero: Node2D, candidates: Array, max_distance: float = 96.0) -> Node2D:
	if hero == null:
		return null
	var eligible: Array[Node2D] = []
	for candidate in candidates:
		if not candidate is Node2D:
			continue
		if hero.global_position.distance_to(candidate.global_position) > max_distance:
			continue
		if candidate.has_method("eligible_for") and not candidate.eligible_for(hero):
			continue
		eligible.append(candidate)
	eligible.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var ap: int = int(a.get("interaction_priority"))
		var bp: int = int(b.get("interaction_priority"))
		if ap != bp:
			return ap > bp
		var ad := hero.global_position.distance_squared_to(a.global_position)
		var bd := hero.global_position.distance_squared_to(b.global_position)
		if not is_equal_approx(ad, bd):
			return ad < bd
		return String(a.get("interaction_id")) < String(b.get("interaction_id")))
	)
	return null if eligible.is_empty() else eligible[0]
```

Add `interaction_kind`, `interaction_priority`, `eligible_for()`, and character requirement fields to `Interactable`. Do not let the resolver activate nodes.

- [ ] **Step 4: Run targeted unit and player tests**

```bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_player_scene.gd
```

Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/player/action_resolver.gd game/world/interactable.gd game/player/player_body.gd game/tests/unit/test_world_rules.gd game/tests/integration/test_player_scene.gd
git commit -m "game: resolve context actions deterministically"
```

---

### Task 3: Damage, Knockback, Spawn Protection, and Gameplay HUD

**Files:**
- Modify: `game/player/player_body.gd`
- Create: `game/ui/gameplay_hud.gd`
- Create: `game/ui/gameplay_hud.tscn`
- Modify: `game/tests/integration/test_player_scene.gd`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Produces: `PlayerBody.take_world_hit(source_peer_id: int, impulse: Vector2) -> bool`
- Produces: `PlayerBody.begin_respawn(at_position: Vector2) -> void`
- Produces: `PlayerBody.controls_locked() -> bool`
- Produces: `GameplayHud.render(score: int, rabbit_hearts: int, fox_hearts: int, local_ammo: int) -> void`
- Produces: `GameplayHud.show_context(kind: String) -> void`
- Produces: `GameplayHud.show_score_gain(points: int, world_position: Vector2) -> void`

- [ ] **Step 1: Write failing recovery and HUD tests**

Test that the first hit applies the supplied impulse, a hit during immunity is rejected, zero hearts locks control, one second restores position/hearts, and 1.25 seconds of spawn protection rejects damage. Instantiate `gameplay_hud.tscn` and assert:

```gdscript
hud.render(135, 2, 3, 4)
if hud.get_node("Top/Score").text != "135":
	return _fail_bool("HUD must display authoritative team score")
if hud.get_node("Top/RabbitHearts").get_child_count() != 3:
	return _fail_bool("HUD must retain fixed rabbit heart slots")
if hud.get_node("Ammo").visible == false:
	return _fail_bool("positive local bubble ammo must be visible")
```

- [ ] **Step 2: Run player and visual tests and verify red**

Run the two targeted tests. Expected: missing methods and missing HUD scene.

- [ ] **Step 3: Implement recovery state in `PlayerBody`**

Add constants `RESPAWN_DELAY := 1.0` and `SPAWN_PROTECTION := 1.25`, timers, and a pending respawn position. `physics_step()` counts them down; while respawning it zeros velocity and ignores movement. On expiry call the existing immediate `respawn()` and start spawn protection. Keep `take_hit()` as a compatibility wrapper over `take_world_hit(source_peer_id, Vector2.ZERO)`.

Core transition:

```gdscript
func take_world_hit(source_peer_id: int, impulse: Vector2) -> bool:
	_ensure_initialized()
	if _respawn_remaining > 0.0 or _spawn_protection_remaining > 0.0 or _damage_cooldown_remaining > 0.0:
		return false
	_damage_cooldown_remaining = DAMAGE_COOLDOWN
	_last_damage_source_peer_id = source_peer_id
	hearts -= 1
	velocity = impulse
	if hearts <= 0:
		begin_respawn(checkpoint_position)
	return true
```

- [ ] **Step 4: Build the HUD scene with fixed safe-area anchors**

Use a top `MarginContainer` with Riki hearts left, team score centered, and Foxy hearts right. Use five precreated ammo marks beside the existing action control; toggle visibility instead of allocating marks during play. Use Hebrew-accessible labels but retain icon-first presentation.

- [ ] **Step 5: Run targeted tests and verify green**

Run both targeted tests. Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add game/player/player_body.gd game/ui/gameplay_hud.gd game/ui/gameplay_hud.tscn game/tests/integration/test_player_scene.gd game/tests/integration/test_visual_target.gd
git commit -m "game: add forgiving recovery and gameplay HUD"
```

---

### Task 4: Beetle and Hopping-Seed Actors

**Files:**
- Modify: `game/world/enemy.gd`
- Create: `game/world/enemy_actor.gd`
- Create: `game/world/beetle_enemy.tscn`
- Create: `game/world/seed_enemy.tscn`
- Create: `game/visual/seed_enemy_visual.gd`
- Create: `game/visual/seed_enemy_visual.tscn`
- Create: `game/art/objects/enemy_seed.svg`
- Modify: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Produces: `EnemyActor.configure(enemy_id: String, enemy_kind: String) -> void`
- Produces: `EnemyActor.host_step(delta: float) -> void`
- Produces signal: `world_transition_requested(kind: String, payload: Dictionary)`
- Produces: `EnemyActor.apply_authoritative_state(payload: Dictionary) -> bool`

- [ ] **Step 1: Write failing actor behavior tests**

Instantiate both scenes. Assert beetle patrols within its range and turns, seed spends a telegraph interval before a hop, contact emits one damage request per immunity window, stomp requires descending velocity and foot position above the stomp plane, bubble hit defeats, and repeated defeat state does not emit another transition.

Representative assertion:

```gdscript
var seed = load("res://world/seed_enemy.tscn").instantiate()
root.add_child(seed)
seed.host_step(seed.telegraph_duration * 0.5)
if seed.motion_state != seed.TELEGRAPH:
	_fail("seed must visibly telegraph before hopping")
seed.host_step(seed.telegraph_duration)
if seed.motion_state != seed.HOP or seed.velocity.y >= 0.0:
	_fail("seed hop must begin with upward velocity")
```

- [ ] **Step 2: Run world rules and verify red**

Expected: missing actor scenes.

- [ ] **Step 3: Separate pure enemy state from scene collision**

Keep `Enemy` as the deterministic rules/state holder. Add `enemy_kind`, `TELEGRAPH`, and `HOP`; make `host_step()` return a state snapshot without directly scoring. `EnemyActor` owns an `Area2D` hurt sensor, a top stomp sensor, and optional `CharacterBody2D` motion for the hopping variant. It emits requests and only disables collision in `apply_authoritative_state({"state": "defeated"})`.

- [ ] **Step 4: Create bounded enemy scenes and seed SVG**

Each scene contains one actor root, two collision shapes, and one visual child. The seed SVG uses a rounded acorn/seed silhouette, leaf sprout, large eyes, dark-blue outline, and no more than practical gameplay detail. The visual script animates telegraph squash and defeat pop but never changes actor position or velocity.

- [ ] **Step 5: Run world and visual tests**

```bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_visual_target.gd
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add game/world/enemy.gd game/world/enemy_actor.gd game/world/beetle_enemy.tscn game/world/seed_enemy.tscn game/visual/seed_enemy_visual.gd game/visual/seed_enemy_visual.tscn game/art/objects/enemy_seed.svg game/tests/unit/test_world_rules.gd game/tests/integration/test_visual_target.gd
git commit -m "game: add playable beetle and seed enemies"
```

---

### Task 5: Pooled Bubble Projectiles

**Files:**
- Create: `game/world/bubble_projectile.gd`
- Create: `game/world/bubble_projectile.tscn`
- Modify: `game/world/object_pool.gd`
- Modify: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Consumes: `BubbleInventory.consume(peer_id)` from Task 1.
- Produces: `BubbleProjectile.launch(owner_peer_id: int, origin: Vector2, direction: float, sequence: int) -> void`
- Produces: `BubbleProjectile.host_step(delta: float) -> Dictionary`
- Produces signal: `enemy_hit(enemy_id: String, owner_peer_id: int, projectile_id: String)`
- Produces signal: `released(projectile: Node)`

- [ ] **Step 1: Write failing projectile tests**

Assert launch rejects owner 0 and zero direction, moves at its fixed speed, expires at 2.5 seconds, releases once on enemy overlap, cannot hit heroes, and the pool rejects a seventh simultaneous acquisition.

- [ ] **Step 2: Run world rules and verify red**

Expected: missing projectile scene.

- [ ] **Step 3: Implement a resettable pooled projectile**

Use a visible `Area2D` with a circle shape. `launch()` records immutable owner/projectile identity and enables monitoring. `host_step()` moves only on the host and returns `{}` until expiry, then returns `{"kind": "bubble_released", "projectile_id": id}` exactly once. `reset_for_pool()` clears monitoring, visibility, identity, and timers.

- [ ] **Step 4: Enforce pool release hygiene**

Update `ObjectPool.release()` to call `reset_for_pool()` when present before returning the node to the available list. Preserve the existing generic pool test.

- [ ] **Step 5: Run unit tests and verify green**

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add game/world/bubble_projectile.gd game/world/bubble_projectile.tscn game/world/object_pool.gd game/tests/unit/test_world_rules.gd
git commit -m "game: add pooled bubble projectiles"
```

---

### Task 6: Teamwork Gates and Host-Authoritative World Events

**Files:**
- Create: `game/world/teamwork_gate.gd`
- Modify: `game/autoload/session.gd`
- Modify: `game/levels/two_player_level.gd`
- Add: `game/tests/integration/test_sunny_forest_network.gd`
- Modify: `game/tests/unit/test_world_rules.gd`

**Interfaces:**
- Produces: `TeamworkGate.mark_part(part_id: String, peer_id: int) -> bool`
- Produces: `TeamworkGate.snapshot() -> Dictionary`
- Produces: `Session.is_host() -> bool`
- Produces: `Session.authoritative_snapshot() -> Dictionary`
- Produces: `TwoPlayerLevel.request_world_action(action_id: String, target_id: String, hero_position: Vector2) -> void`
- Produces hook: `_validate_world_action(peer_id: int, action_id: String, target_id: String, hero_position: Vector2) -> Dictionary`
- Produces hook: `_apply_world_event(sequence: int, kind: String, payload: Dictionary) -> void`
- Produces hook: `_world_snapshot() -> Dictionary`
- Produces hook: `_restore_world_snapshot(snapshot: Dictionary) -> bool`

- [ ] **Step 1: Write failing gate and network validation tests**

Test two unique parts complete once, duplicate parts do not complete twice, and restore round-trips. In the integration test, instantiate a small `TwoPlayerLevel` test subclass and assert:

```gdscript
level.receive_world_action_for_test(2, 1, "push", "log", Vector2(500, 0))
if level.applied_event_count != 0:
	_fail("out-of-range world action must be rejected")
level.receive_world_action_for_test(2, 2, "push", "log", Vector2(40, 0))
level.receive_world_action_for_test(2, 2, "push", "log", Vector2(40, 0))
if level.applied_event_count != 1:
	_fail("duplicate client sequence must apply once")
```

- [ ] **Step 2: Run tests and verify red**

Expected: missing gate and transport interfaces.

- [ ] **Step 3: Add read-only session accessors**

```gdscript
func is_host() -> bool:
	return _is_host

func authoritative_snapshot() -> Dictionary:
	return _authoritative_snapshot.duplicate(true)
```

Do not expose mutable peer internals.

- [ ] **Step 4: Add reliable request and ordered event RPCs**

Maintain `_last_request_sequence_by_peer`, `_next_local_request_sequence`, `_next_world_event_sequence`, and `_last_applied_world_event_sequence`. Host validation derives the sender from `multiplayer.get_remote_sender_id()`; it never trusts a peer ID in payload data. Test-only delivery calls the same private validator path.

```gdscript
@rpc("any_peer", "reliable")
func _receive_world_action(request_sequence: int, action_id: String, target_id: String, hero_position: Vector2) -> void:
	if not _is_authority_for_world():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_process_world_action(peer_id, request_sequence, action_id, target_id, hero_position)

@rpc("authority", "reliable")
func _receive_world_event(event_sequence: int, kind: String, payload: Dictionary) -> void:
	if event_sequence <= _last_applied_world_event_sequence:
		return
	_last_applied_world_event_sequence = event_sequence
	_apply_world_event(event_sequence, kind, payload)
```

- [ ] **Step 5: Pause shared simulation with the existing session state**

Make the base `_physics_process()` skip `_step_level`, enemy/projectile host steps, and new requests while `Session.state == Session.RECONNECTING`; keep UI presentation active. On resume restore the authoritative snapshot before accepting another world request.

- [ ] **Step 6: Run unit, network, session-pair, and reconnect tests**

```bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest_network.gd
bash scripts/run_lan_pair.sh
bash scripts/run_reconnect_pair.sh
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```bash
git add game/world/teamwork_gate.gd game/autoload/session.gd game/levels/two_player_level.gd game/tests/unit/test_world_rules.gd game/tests/integration/test_sunny_forest_network.gd
git commit -m "game: synchronize authoritative world events"
```

---

### Task 7: Compose the Complete Sunny Forest Level

**Files:**
- Modify: `game/levels/coop_level.gd`
- Modify: `game/levels/sunny_forest.gd`
- Modify: `game/levels/sunny_forest.tscn`
- Create: `game/art/objects/fallen_log.svg`
- Create: `game/art/objects/pressure_flower.svg`
- Create: `game/art/objects/bubble_flower.svg`
- Create: `game/art/environment/sunny_forest/magical_tree.svg`
- Create: `game/visual/magical_tree_visual.gd`
- Create: `game/visual/magical_tree_visual.tscn`
- Modify: `game/tests/integration/test_sunny_forest.gd`

**Interfaces:**
- Consumes all interfaces from Tasks 1–6.
- Produces: a complete `SunnyForest` world snapshot containing score, collected IDs, checkpoint, enemies, gates, ammo, projectiles, and world-event sequence.
- Produces: the existing `level_finished(result: Dictionary)` signal with `stars_collected` and new `team_score` fields.

- [ ] **Step 1: Replace node-count assertions with failing experience assertions**

Keep reachability and budget checks, then add scripted progression:

```gdscript
level.collect_star_for_test("meadow-star-1", 1)
level.collect_star_for_test("meadow-star-1", 2)
if level.team_score.total != 10:
	_fail("simultaneous star collection must score once")
level.complete_log_part_for_test("log", 2)
level.complete_log_part_for_test("overhead_switch", 1)
if not level.gate_is_open("fallen_log") or level.team_score.total != 110:
	_fail("two distinct role actions must open and score the log gate")
level.complete_pressure_part_for_test("left_flower", 1)
level.complete_pressure_part_for_test("right_flower", 2)
if not level.gate_is_open("bubble_grove"):
	_fail("both pressure flowers must open Bubble Grove")
level.enter_finish_for_test(1)
if level.is_finished():
	_fail("one hero cannot finish cooperative level alone")
level.enter_finish_for_test(2)
if not level.is_finished():
	_fail("both heroes at magical tree must finish level")
```

- [ ] **Step 2: Run Sunny Forest test and verify red**

Expected: missing gameplay interfaces.

- [ ] **Step 3: Re-layout the scene into four named sections**

Use stable node roots `SunlitMeadow`, `FallenLogCrossing`, `BubbleGrove`, and `MagicalTreeFinish`. Place a checkpoint after Meadow and at the end of Bubble Grove. Add safe ground and reunion paths first, then optional elevated star paths. Use named markers for enemy patrol bounds, push destination, switch, pressure flowers, bubble pickup, and finish.

- [ ] **Step 4: Orchestrate actions and authoritative events**

`SunnyForest._validate_world_action()` maps known target IDs to interactions, checks current authoritative hero position (not only the request's claimed position), checks Foxy for push and Riki for overhead switch, checks range, and returns a compact event dictionary. `_apply_world_event()` performs idempotent score, enemy, gate, pickup, ammo, projectile, and finish transitions.

- [ ] **Step 5: Implement checkpoint and finish payloads**

Checkpoint snapshot includes both hero positions, score, collected IDs, gate/enemy states, and ammo. Finish waits for both peer IDs, locks input, plays a 1.2-second celebration, and calls:

```gdscript
coop_mode.complete_level()
```

Extend the result in `CoopLevel`:

```gdscript
"stars_collected": _collected_stars,
"team_score": team_score.total,
```

- [ ] **Step 6: Run Sunny Forest, app shell, and world tests**

```bash
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
godot --headless --path game -s res://tests/integration/test_app_shell.gd
godot --headless --path game -s res://tests/unit/test_world_rules.gd
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add game/levels/coop_level.gd game/levels/sunny_forest.gd game/levels/sunny_forest.tscn game/art/objects/fallen_log.svg game/art/objects/pressure_flower.svg game/art/objects/bubble_flower.svg game/art/environment/sunny_forest/magical_tree.svg game/visual/magical_tree_visual.gd game/visual/magical_tree_visual.tscn game/tests/integration/test_sunny_forest.gd
git commit -m "game: build complete Sunny Forest objectives"
```

---

### Task 8: Animated Storybook Presentation and Audio Feedback

**Files:**
- Modify: `game/art/characters/riki_rabbit.svg`
- Modify: `game/art/characters/foxy_fox.svg`
- Add focused part SVGs only if required by the hero scene; keep them under `game/art/characters/`.
- Add: `game/art/environment/sunny_forest/near_trees.svg`
- Add: `game/art/environment/sunny_forest/leaf_frame.svg`
- Modify: `game/visual/hero_visual.gd`
- Modify: `game/visual/hero_visual.tscn`
- Modify: `game/visual/sunny_forest_background.gd`
- Modify: `game/visual/sunny_forest_background.tscn`
- Modify: `game/visual/collectible_visual.gd`
- Modify: `game/visual/checkpoint_visual.gd`
- Modify: `game/audio/audio_director.gd`
- Modify: `game/ui/results_screen.gd`
- Modify: `game/tests/integration/test_visual_target.gd`
- Modify: `game/tests/integration/test_results_flow.gd`

**Interfaces:**
- Consumes gameplay signals and snapshots from prior tasks.
- Produces: `HeroVisual.play_celebration() -> void`
- Produces: `AudioDirector.play_gameplay_cue(cue: String, peer_id: int = 0) -> bool`

- [ ] **Step 1: Write failing presentation and results assertions**

Assert the background has `Sky`, `Far`, `Mid`, `Near`, and `Frame` layers with distinct ratios; hero visuals expose idle/run/jump/action/damage/celebration state application without mutating parent physics; new object visuals load; HUD feedback nodes are bounded; and the results screen displays `team_score` plus `stars_collected`.

- [ ] **Step 2: Run visual and result tests and verify red**

Expected: missing Near layer, celebration interface, and score result display.

- [ ] **Step 3: Build the Animated Storybook layers and richer hero rigs**

Keep original characters but separate presentation into head, ears/tail, torso, arms, and feet. Drive transforms from velocity and explicit visual events:

- Idle: breathing plus infrequent blink and ear/tail secondary motion.
- Run: alternating feet, body bob, forward lean.
- Jump: ascent stretch and fall tuck.
- Action: 0.16-second forward gesture.
- Damage: brief recoil without full-screen flashing.
- Respawn: warm scale-in.
- Finish: 1.2-second alternating hops and star burst.

Add closer tree clusters and leaf framing at conservative parallax ratios. Keep all gameplay surfaces visually distinct and cover every collider.

- [ ] **Step 4: Add named bounded audio cues**

Map cue names to short offsets/streams already licensed in the repository. Return `false` for unknown cues. Reuse the existing SFX voice pool and projectile voice cap; do not allocate one player per event.

- [ ] **Step 5: Render and visually inspect the level**

Run the Godot editor or a repository screenshot helper if present. Capture a 1340×800 frame from Meadow, Fallen Log, Bubble Grove, and Magical Tree. Confirm heroes, enemies, traversable surfaces, prompt, score, hearts, ammo, and controls remain readable. Do not commit temporary screenshots unless they are intentional test evidence.

- [ ] **Step 6: Run targeted tests and verify green**

```bash
godot --headless --path game -s res://tests/integration/test_visual_target.gd
godot --headless --path game -s res://tests/integration/test_results_flow.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add game/art game/visual game/audio/audio_director.gd game/ui/results_screen.gd game/tests/integration/test_visual_target.gd game/tests/integration/test_results_flow.gd game/tests/integration/test_sunny_forest.gd
git commit -m "game: polish Sunny Forest storybook presentation"
```

---

### Task 9: Full Verification, APK, and Tablet Handoff

**Files:**
- Modify documentation only if actual verification output changes an existing truthful status.
- Do not mark physical evidence gates passed without the operator-run tablet session.

**Interfaces:**
- Consumes the complete vertical slice.
- Produces a verified debug APK and an explicit operator smoke checklist.

- [ ] **Step 1: Run metadata and repository checks**

```bash
git diff --check
python3 -m deploy.animal_heroes_deploy --check
```

Expected: exit 0. If deploy config is incomplete, report the exact validation message and continue only with game-local checks that remain valid.

- [ ] **Step 2: Run targeted game and LAN tests**

```bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest_network.gd
godot --headless --path game -s res://tests/integration/test_visual_target.gd
bash scripts/run_lan_pair.sh
bash scripts/run_reconnect_pair.sh
```

Expected: all commands exit 0.

- [ ] **Step 3: Run the canonical full game gate**

```bash
bash scripts/test_all.sh
```

Expected: exit 0 with every discovered Godot test, LAN/reconnect test, performance budget, permission contract, and faked device-smoke contract passing.

- [ ] **Step 4: Run deploy-service tests**

```bash
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v
```

Expected: all tests pass.

- [ ] **Step 5: Build and audit the debug APK**

```bash
bash scripts/build_android.sh
```

Expected: `build/animal-heroes-debug.apk`, checksum, and idsig are produced; the permission audit reports exactly the four allowed permissions.

- [ ] **Step 6: Inspect final changes**

```bash
git status --short
git diff --stat HEAD~1..HEAD
```

Confirm only intended game, test, art, plan, and spec files changed; preserve all pre-existing user-owned `docs/test-results/` files.

- [ ] **Step 7: Provide the real-tablet operator command without running gameplay unattended**

After resolving Android tools and the two tablet serials, the operator runs:

```bash
HOST_SERIAL=<host-serial> CLIENT_SERIAL=<client-serial> bash scripts/device_smoke.sh
```

During the ten-minute interval, the operator must host/join, complete all four Sunny Forest sections, use both role actions, stomp and bubble enemies, lose/restore hearts, activate checkpoints, verify equal scores, finish together, and inspect the results screen. Then parse:

```bash
python3 scripts/parse_smoke_results.py docs/test-results
```

Do not claim the physical 30 FPS or usability gates until that real run completes.

- [ ] **Step 8: Commit truthful documentation updates, if any**

```bash
git add docs/release-checklist.md docs/test-results
git commit -m "docs: record Sunny Forest tablet evidence"
```

Run this step only when the operator has produced new evidence and explicitly wants it committed. Otherwise leave those files untouched.
