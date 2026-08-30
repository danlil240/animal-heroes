# Bot Pair Gameplay Findings

Two agent players (Riki the rabbit + Foxy the fox) were driven through the
cooperative campaign via the real input pipeline
(`game/tests/integration/test_bot_pair.gd`, run by `scripts/run_bot_pair.sh`).
Each hero is controlled by a small bot that chases the nearest collectible /
powerup / enemy, jumps periodically and when stuck or chasing a target above
it, and pulses the context action so both the rising-edge and held-fire code
paths execute. Input is injected through the production routes:
`TouchControls._keyboard` for the local hero and `TwoPlayerLevel._remote_keys`
for the partner, so the authoritative action loop, bubble pool, SFX voices,
enemies, and fall-respawn zones are all exercised for real.

Raw per-level metrics are in `game/test-output/bot_pair_report.md`; raw godot
logs are in `game/test-output/bot_pair_<level>.log`.

## Gameplay results (1800 frames ≈ 60s each)

| Level | finished | team_score | stars | enemies left | hearts (R/F) | bubbles max | notes |
|---|---|---|---|---|---|---|---|
| sunny_forest | no | 100 | 0 | 4 | 3 / 4 | 6 | bubble pool saturated; shots rejected |
| crystal_caves | no | 0 | 0 | 0 | 3 / 4 | 0 | **both heroes fell to y ≈ 1,700,000** |
| cloud_factory | no | 0 | 0 | 0 | 3 / 4 | 0 | bots traversed rightward; no scoring objects reached |

The bots did not finish any level in 60 s, which itself is informative: every
level either trapped the heroes (crystal_caves) or denied the primary weapon
(sunny_forest). cloud_factory has no `enemy`-group actors in reach of the
spawn side, so the bots had nothing to score against.

## Bugs found

### Bug 1 — CRITICAL: Crystal Caves heroes fall forever off the left edge

**Evidence:** after 60 s, `rabbit_pos=(-179, 1779537)`, `fox_pos=(-145, 1405224)`.
Both heroes walked left past the ground edge and descended ~1.7 million pixels
with no respawn.

**Root cause:** `levels/crystal_caves.tscn`
- `Ground` at `(1600, 720)`, shape `3200 x 80` → covers x ∈ [0, 3200].
- `FallRespawn` at `(1600, 930)`, shape `3400 x 120` → covers x ∈ [-100, 3300].

The fall zone extends only 100 px left of the ground's left edge (x=0). A hero
that walks off the left edge at x < -100 falls outside the `FallRespawn` Area2D,
so `body_entered` never fires and `_respawn_fallen_hero` is never called. The
hero accelerates under gravity indefinitely. `sunny_forest` and `cloud_factory`
share the same FallRespawn dimensions (`3400 x 120` at `(1600, 930)`), so the
same trap exists wherever a hero can leave the ground horizontally.

**Fix:** widen `FallShape` so it extends well beyond both ground edges on every
level (e.g. x ∈ [-400, 3600] → size `4000 x 120` at `(1600, 930)`), or add
invisible side walls at the ground edges. The fall zone must cover every
position a hero can reach while falling, including horizontal drift during a
fall.

### Bug 2 — Sunny Forest bubble pool exhausts under two-player spread fire

**Evidence:** `pool_exhausted=true`, `max_active_bubbles=6`, `active_bubbles=6`.
Once the pool fills, every subsequent shot sequence is rejected
(`levels/sunny_forest.gd:489` prints "Sunny Forest bubble pool exhausted; shot
sequence rejected"). This is the same error the operator hit during manual play.

**Root cause:** `levels/sunny_forest.gd:37` configures `_bubble_pool` with a
capacity of **6**. A spread shot fires a 3-bubble fan (`SPREAD_VERTICAL_VELOCITIES`
has 3 entries). Two players firing one spread each consumes all 6 slots
instantly. Bubbles live 2.5 s (`BubbleProjectile.LIFETIME`), so under continuous
two-player fire the pool is permanently full and `fire_bubble` rejects every new
sequence at `sunny_forest.gd:126`. The weapon is effectively dead for both
players after the first burst.

**Fix:** raise the bubble pool capacity to at least `2 players * 3 fan * ceil(
FIRE_INTERVAL / LIFETIME)` worth of in-flight bubbles, or release bubbles on
out-of-bounds immediately (currently they fly the full 2.5 s even off-screen).
A capacity of 12–18 removes the false exhaustion under sustained two-player
spread fire while staying inside the `projectile_budget <= 24` device ceiling.

### Bug 3 — AudioDirector: projectile-voice `finished` signal double-connect

**Evidence (operator's rendered run):**
```
ERROR: Signal 'finished' is already connected to given callable
       'Node(audio_director.gd)::_on_projectile_voice_finished' in that object.
   at: connect (core/object/object.cpp:1562)
       [0] play_sfx (res://audio/audio_director.gd:116)
       [1] play_gameplay_cue (res://audio/audio_director.gd:151)
       [2] fire_bubble (res://levels/sunny_forest.gd:150)
```
This fires on every bubble shot in a rendered (audio-active) session. It did
not appear in the headless run because headless Godot does not advance
`AudioStreamPlayer` playback, so `finished` never emits and the voice counter
saturates at `MAX_PROJECTILE_VOICES` instead — a different failure mode of the
same fragile bookkeeping (see below).

**Root cause:** `audio/audio_director.gd:115-119`:
```gdscript
if is_projectile:
    if player.finished.is_connected(_on_projectile_voice_finished):
        player.finished.disconnect(_on_projectile_voice_finished)
        _projectile_voices_in_use = maxi(_projectile_voices_in_use - 1, 0)
    player.finished.connect(_on_projectile_voice_finished, CONNECT_ONE_SHOT)
```
`_find_available_sfx_player()` returns any player with `playing == false`. A
player whose previous projectile sound just ended can be returned while its
ONE_SHOT `finished` connection is still being torn down, so `is_connected()`
and `connect()` disagree and `connect` raises "already connected". The manual
`disconnect` + `CONNECT_ONE_SHOT` combination also double-decrements
`_projectile_voices_in_use` in some orderings, and in headless mode the counter
leaks to `MAX_PROJECTILE_VOICES` and permanently mutes projectile SFX.

**Fix:** drop the manual disconnect and make the connect unconditional-safe:
```gdscript
if is_projectile:
    if not player.finished.is_connected(_on_projectile_voice_finished):
        player.finished.connect(_on_projectile_voice_finished, CONNECT_ONE_SHOT)
    player.finished.emit  # no-op guard not needed; just avoid reconnect
```
Better: give projectile voices their own dedicated `AudioStreamPlayer` pool of
`MAX_PROJECTILE_VOICES` players, each connected once at `_ready`, and track
in-use via the player's `playing` state instead of a hand-maintained counter.
That removes the connect/disconnect race entirely.

### Bug 4 — Minor: resources still in use at exit

**Evidence:** `ERROR: N resources still in use at exit` on all three levels
(`game/test-output/bot_pair_*.log`).

**Root cause:** the harness calls `level.queue_free()` then `quit(0)` on the
next frame without waiting for the freed subtree to fully release its loaded
resources. This is a harness-cleanup artifact, not a gameplay leak, but it
indicates the level subtrees hold onto loaded resources (audio streams,
textures) past `queue_free`. Worth confirming with a longer await; if it
persists outside the harness it suggests resources are cached on nodes that
outlive the level.

## Reproducing

```bash
bash scripts/run_bot_pair.sh
# or a single level:
godot --headless --path game -s res://tests/integration/test_bot_pair.gd \
    -- --level=crystal_caves --frames=1800
```

To reproduce Bug 3 (audio double-connect) run with rendering/audio, as the
operator did:
```bash
godot --path game res://levels/sunny_forest.tscn   # then fire bubbles
```
