# Sunny Forest Complete Vertical Slice — Design Specification

Date: 2026-08-29
Status: Approved in conversation

## 1. Goal

Turn Sunny Forest from a movement-and-collection prototype into an 8–10 minute cooperative level that is satisfying on both SM-T220 tablets. The level must prove the complete production loop—movement, context actions, enemies, health, power-ups, teamwork, scoring, checkpoints, presentation, audio, LAN consistency, results, and progression—before the same systems are reused by later levels.

## 2. Audience and Constraints

- Primary players are children aged four to five.
- The existing large left, right, jump, and action touch controls remain the complete control set.
- Both tablets run the same APK; the host owns shared world outcomes.
- The level must remain playable without internet access or external services.
- The minimum target is 30 FPS on each SM-T220.
- No third-party dependencies are added.
- Physics and network tick rates remain unchanged.
- The Android package ID and exact four-permission allowlist remain unchanged.
- Mistakes cause quick recovery, never finite lives or a game-over screen.

## 3. Player Experience

The heroes travel through four connected sections toward a magical tree. Stars reward exploration but never block progress. Each section teaches one idea, gives immediate visual and audio feedback, and ends with either a checkpoint or a celebration. A successful first run lasts 8–10 minutes; a skilled replay may be shorter.

### Section 1: Sunlit Meadow

- Animated signs demonstrate walking, jumping, and stomping without requiring reading.
- Slow beetles patrol safe ground ranges.
- A raised optional route contains stars while the lower route remains safe.
- The section ends at a checkpoint flower.

### Section 2: Fallen-Log Crossing

- Foxy pushes a heavy log into a bridge position.
- Riki uses the higher jump to reach an overhead flower switch.
- The two actions may happen in either order.
- The layout contains a safe reunion route and cannot trap either hero.
- Completing both actions opens the way and awards a teamwork bonus.

### Section 3: Bubble Grove

- A bubble flower grants five shots to the collecting hero.
- Hopping seed creatures use a readable arc and are easiest to defeat with bubbles.
- Two separated pressure flowers require both heroes to stand in place together.
- The path opens, awards a teamwork bonus, and leads to the final checkpoint.

### Section 4: Magical Tree

- Both heroes enter a large glowing finish area.
- The level locks input, plays a short joint celebration, and emits one completion result.
- The results screen shows the shared score and stars collected, celebrates both heroes, and unlocks Crystal Caves.

## 4. Controls and Context Action

Movement and jump remain immediate and locally simulated. The action button is context-sensitive:

1. Find eligible interactables within a 96-pixel radius of the local hero.
2. Prefer a highlighted teamwork object over a power-up shot.
3. Pick the closest eligible object with a stable node-path tie-break.
4. Send one reliable action request to the host on the rising edge of the button press.
5. If no eligible interactable exists and the hero has bubble ammunition, fire one bubble.
6. If neither action is available, play a quiet unavailable cue without changing world state.

An eligible object gains a high-contrast outline and an icon above it. The action button changes its small context icon between hand, push, switch, and bubble while its location and 128-pixel touch target remain fixed.

## 5. Character Roles

- Riki retains the faster movement and higher jump.
- Foxy retains the additional heart profile property and ability to push heavy objects.
- Ordinary routes never require a character-specific ability.
- Only the Fallen-Log teamwork gate uses the distinct roles.
- Interaction prompts use icons, color, and motion rather than Hebrew text alone.

## 6. Enemies and Combat

### Beetle

- Patrols a fixed horizontal range at a slow speed.
- Turns at configured limits and never walks off its platform.
- Contact removes one heart and applies a short horizontal/upward bounce.
- A descending hero whose feet cross the beetle's stomp zone defeats it and receives a small upward rebound.

### Hopping seed

- Waits, telegraphs with a squash, then follows a fixed parabolic hop.
- Contact uses the same damage and immunity rules as the beetle.
- A stomp or one bubble hit defeats it.

### Shared behavior

- Defeat awards 25 team points exactly once.
- Defeated enemies disable collision, play a bounded comic puff, then remain absent for the run.
- No enemy is placed where it can repeatedly hit a respawning hero.
- The host advances enemy state and validates defeats; clients render authoritative results.

## 7. Health, Damage, and Recovery

- Each hero starts with the profile's configured maximum hearts; the current profiles produce three or more hearts as already defined.
- Valid contact damage removes one heart and starts the existing 0.75-second immunity window.
- Damage produces knockback, a non-flashing red recoil, a short sound, and a HUD heart animation.
- At zero hearts, or after entering the fall zone, the hero loses control for one second and respawns at the latest shared checkpoint.
- Respawn restores maximum hearts and grants 1.25 seconds of spawn protection.
- A checkpoint updates both heroes' respawn positions, persists the confirmed checkpoint through `Session`, and cannot double-score.
- There are no lives, game-over screens, score penalties, or progress loss.

## 8. Bubble Power-Up

- A bubble flower grants exactly five shots to the collecting hero.
- Remaining ammunition appears beside the action button as five small bubble marks.
- A bubble travels horizontally at a moderate speed, lasts at most 2.5 seconds, and is released on collision or expiry.
- Each hero may own at most three active bubbles; the entire level may contain at most six.
- Bubble scenes are preallocated through the existing object-pool mechanism.
- A bubble can defeat an enemy but cannot damage heroes or activate teamwork objects.
- Collection, firing, collision, and ammunition changes are host-authoritative shared events.

## 9. Shared Scoreboard and HUD

The HUD displays:

- One shared team score in the upper center.
- Riki's hearts in the upper left.
- Foxy's hearts in the upper right.
- Bubble ammunition beside the local action button when nonzero.
- The existing partner direction indicator when the other hero is off-screen.

Scoring is fixed:

- Star: 10 points.
- Enemy: 25 points.
- Completed teamwork gate: 100 points.

The host owns the integer score and a set of already-scored event IDs. Replayed, duplicate, late, or reconnected messages cannot score twice. Score never decreases. Both tablets display the same score from authoritative snapshots/events.

## 10. LAN Authority and Synchronization

Player movement keeps the existing responsive local-owner model. Shared world interactions use a new level event channel:

- Client sends `request_world_action(action_id, target_id, hero_position, sequence)` reliably to the host.
- Host checks sender identity, monotonically increasing sequence, level ID, target existence, target state, character eligibility, and current authoritative distance.
- Host applies the valid action and broadcasts an ordered `world_event` containing an event sequence and compact payload.
- Both peers apply the event idempotently.
- Host periodically includes score, checkpoint, enemy states, gate states, collectible IDs, bubble ammunition, and event sequence in `Session.set_authoritative_snapshot()`.
- Reconnect restores the snapshot before play resumes.

Invalid, stale, duplicated, out-of-range, wrong-character, or unknown-target requests are ignored without changing score or world state. They may emit a bounded diagnostic locally but never display a child-facing error.

## 11. Visual Direction

The approved direction is **Animated Storybook**:

- Layered sky, distant hills, midground foliage, and foreground framing use distinct parallax ratios.
- Characters gain separable face, ear/tail, body, arm, and foot presentation nodes so idle, run, jump, action, damage, and celebration poses read clearly.
- Heroes keep dark blue outlines and saturated clothing identities.
- Platforms gain richer grass edges, soil facets, flowers, mushrooms, and small non-colliding props without implying false surfaces.
- Beetle, hopping seed, bubble flower, log, pressure flowers, and magical tree receive original illustrated SVG assets with large silhouettes.
- Stars, hits, defeat puffs, checkpoint activation, score additions, and gate completion use bounded particles and tweened transforms.
- No full-screen shader, dynamic light, blur, or unbounded particle emitter is introduced.

Gameplay physics nodes remain authoritative; presentation stays in child visual scenes and never mutates movement state.

## 12. Audio and Feedback

- Existing Sunny Forest music continues through `AudioDirector`.
- Distinct short cues cover jump, star, stomp, damage, checkpoint, bubble pickup, bubble fire, teamwork gate, unavailable action, and level finish.
- The existing bounded SFX voice pool remains in use.
- Every audio event has matching visual feedback.
- Repeated events such as projectiles respect the existing projectile voice limit.

## 13. Scene and Code Boundaries

- `SunnyForest` coordinates the section objectives and finish flow.
- `TeamScore` owns the score and duplicate-event protection.
- `ActionResolver` selects context targets without changing them.
- Enemy actors own local presentation while the level applies authoritative transitions.
- `BubbleInventory` owns per-peer ammunition; `BubbleProjectile` owns one pooled projectile lifecycle.
- `GameplayHud` renders score, hearts, ammo, feedback, and context prompts.
- `TwoPlayerLevel` transports generic world requests/events and snapshots without Sunny Forest-specific rules.
- `Session` exposes whether the local peer is host and retains the authoritative snapshot; it does not interpret level-specific payloads.

Each unit must be testable without loading the entire application shell.

## 14. Error and Edge-Case Behavior

- Two simultaneous star overlaps award once.
- Two simultaneous attacks on one enemy defeat and score it once.
- An action held across frames produces one request until released and pressed again.
- A hero leaving a context radius before host validation causes safe rejection.
- A disconnect pauses the level through the existing overlay; timers, enemies, and projectiles do not advance while paused.
- A hero cannot become trapped behind a closed gate; each teamwork section has a reunion route.
- If optional visual or audio nodes are missing, gameplay continues and emits a diagnostic.
- If a required gameplay node is missing, the level refuses to start and returns to the menu through the existing session-error path.

## 15. Testing and Acceptance

Automated tests must prove behavior, not only node presence:

- Context priority, stable tie-break, single rising-edge action, and wrong-character rejection.
- Exact scoring and duplicate prevention for stars, enemies, and teamwork gates.
- Beetle patrol/contact/stomp and seed telegraph/hop/bubble defeat.
- Damage immunity, knockback, zero-heart respawn, spawn protection, and shared checkpoint placement.
- Bubble ammunition, pooling, per-owner/level caps, collision, and expiry.
- Sunny Forest objective sequence, non-trapping routes, optional stars, two-player finish, result payload, and Crystal Caves unlock.
- Host validation of sender, sequence, target, range, and character ability.
- Two-process equality of score, enemy/gate/collectible state, and checkpoint after actions and reconnect.
- HUD visibility, RTL-safe heart placement, fixed LTR touch controls, 128-pixel targets, and absence of physics mutation from presentation.
- Entity and particle counts remain within existing SM-T220 budgets.

Completion requires:

1. Targeted unit and integration tests pass.
2. `bash scripts/test_all.sh` passes.
3. Deploy unit tests pass.
4. The debug APK builds and passes the exact permission audit.
5. Both tablets complete the level together during an operator-driven smoke run.
6. Captured physical evidence shows a minimum of 30 FPS and no new crash/error loop.

Automated and desktop verification may complete before tablet play. The work must not claim physical performance or usability gates until the operator performs the real two-tablet run.

## 16. Out of Scope

- Rebuilding Crystal Caves, Cloud Factory, the boss, or competitive arenas.
- Adding new characters, currencies, shops, accounts, online play, or more than two players.
- Replacing the deployment service.
- Changing physics/network tick rates or weakening release, signer, permission, or evidence gates.
