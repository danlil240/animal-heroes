# Animal Heroes LAN Game — Design Specification

Date: 2026-08-27
Status: Approved design draft, pending final spec review by the user

## 1. Product Summary

Animal Heroes is a Hebrew-language, two-player 2D platform game for two identical Samsung Galaxy Tab A7 Lite Wi-Fi tablets (SM-T220). It combines cooperative platforming with short friendly competitions. The game works entirely over the local Wi-Fi network, requires no internet service or user account, and contains no advertisements or in-app purchases.

The visual direction is a bright, energetic 1990s cartoon style with saturated colors, expressive animation, and large readable shapes. The gameplay is inspired by the pace and accessibility of classic side-scrolling platform games while using original characters, worlds, art, audio, and mechanics.

## 2. Audience and Design Goals

The primary players are children aged four to five. The game must therefore:

- Be playable with three large touch controls: left/right movement, jump, and action.
- Use icons, animation, and audio cues instead of relying on reading.
- Avoid realistic violence, permanent elimination, long waits, and harsh penalties.
- Keep cooperative sessions engaging for both players even when their skill levels differ.
- Run smoothly and remain visually readable on the SM-T220's 8.7-inch display.
- Recover gracefully from brief Wi-Fi interruptions and tablet sleep/wake cycles.

## 3. Target Platform and Technology

- Engine: Godot 4.x.
- Client platform: Android APK installed directly on each tablet.
- Orientation: landscape only.
- Hardware baseline: Samsung Galaxy Tab A7 Lite Wi-Fi, model SM-T220.
- Rendering target: stable 30 FPS minimum during all supported two-player gameplay.
- Networking: Godot ENet multiplayer over local Wi-Fi, with UDP broadcast discovery.
- External services: none.

Both tablets run the same APK. One instance hosts the authoritative match and the other joins as a client.

## 4. Characters

The game has two visually distinct animal heroes:

- **Riki the Rabbit:** slightly faster movement and a higher jump.
- **Foxy the Fox:** can push heavy objects and has one additional heart.

Both characters can run, jump, activate objects, defeat suitable enemies by landing on them, and use temporary cartoon power-ups. Character differences must add variety without making either hero necessary for ordinary movement through a level. Cooperative gates may require the two heroes' complementary abilities.

## 5. Controls and Camera

Each tablet controls one character. The lower-left corner contains a large semi-transparent left/right control. The lower-right corner contains large jump and action buttons. Controls provide immediate visual and optional vibration feedback.

Each tablet uses a local camera that follows its own character. The camera zooms out within a conservative limit when both players are nearby. A directional partner indicator appears at the screen edge when the other player is outside the view.

The action button activates switches and uses the currently held power-up. Context determines the action, and only one nearby interactable can be highlighted at a time.

## 6. Cooperative Campaign

The campaign contains three levels and one concluding boss encounter. A complete first playthrough should take approximately 30–45 minutes.

### Level 1: The Sunny Forest

Introduces movement, jumping, collectibles, checkpoints, simple enemies, power-ups, and basic partner assistance. The opening section uses animated demonstrations rather than written instructions.

### Level 2: Crystal Caves

Introduces moving platforms, switches, doors, light hazards, and cooperative puzzles. Some sequences require one player to hold a switch while the other crosses, followed by an accessible route that reunites them.

### Level 3: Cloud Factory

Introduces fans, conveyor belts, moving machinery, and more demanding but forgiving jumps. The level reuses learned mechanics in combinations and ends at the boss arena.

### Boss Encounter

The boss is a large comical robot. Players avoid clearly telegraphed attacks, activate two separated switches, and attack exposed weak points using jumps or temporary bubble/star power-ups. Both players contribute to each phase. A failed phase restarts quickly from the current boss checkpoint.

## 7. Competitive Modes

Competitive rounds last approximately two to four minutes. No mode removes a player from the match.

- **Star Race:** both players traverse parallel or shared routes toward the finish. Checkpoints prevent large setbacks. The first finisher wins; the second player may finish the course during a short grace period.
- **Treasure Dash:** players collect fruit, gems, and stars until the timer expires. Higher-value items appear in positions that encourage movement rather than camping.
- **Bubble Bounce:** harmless bubble hits award points and briefly bounce the target backward. Players immediately retain control, and repeated-hit protection prevents stun locking.

Results use celebratory animations for both players. The winner receives a crown or ribbon; the other player receives a positive participation animation. Rematch and mode-selection buttons are equally prominent.

## 8. Health, Failure, and Progression

Players have hearts and respawn quickly at the latest checkpoint after losing them or falling. A player cannot permanently block campaign progress. If one child reaches a checkpoint first, the other player's next respawn uses that checkpoint.

Campaign completion unlocks levels locally. Both tablets record completed levels after a successful synchronized session. There is no currency, purchasing system, account, or online leaderboard.

## 9. Power-Ups, Enemies, and Collectibles

Temporary power-ups fire bubbles, stars, or similarly harmless fantasy projectiles. Power-ups have a clear duration or limited number of uses and never resemble realistic weapons.

Enemies use simple, readable movement patterns. They are defeated by a jump or power-up hit and disappear in a comic puff before later respawning if required. Collectibles include fruit, gems, and stars with distinct silhouettes and sounds.

Objects that appear frequently during play are pooled to minimize runtime allocation and frame-time spikes on the target hardware.

## 10. Hebrew Interface

All menus and status messages use right-to-left Hebrew. The home screen presents four large options:

- משחק משותף
- תחרות
- איך משחקים
- הגדרות

The session flow uses large visual choices for creating and joining a game. Brief status messages explain discovery, connection, pause, and reconnection. The tutorial combines short Hebrew labels with animated control demonstrations.

Music and sound-effect volume are adjustable independently. Optional vibration can be disabled. All settings and unlocked progress are stored locally.

## 11. LAN Session Architecture

### Host-authoritative model

The host owns the authoritative state for enemies, hazards, collectibles, damage, scores, checkpoints, timers, and level transitions. Each client owns immediate local input sampling and prediction for its character. The host validates inputs and broadcasts authoritative snapshots. Clients interpolate remote characters and reconcile their own predicted state when necessary.

This prevents score disagreements and divergent world state while preserving responsive local controls.

### Automatic discovery

The host periodically advertises a small discovery packet by UDP broadcast on the local subnet. A joining tablet listens for compatible advertisements and automatically selects the available game. Discovery packets include a protocol version, game version, session identifier, host address, session state, and player capacity.

Discovery retries continue for a bounded interval with visible Hebrew feedback. If multicast or broadcast behavior is restricted by the access point, the interface exposes a secondary manual connection screen as a recovery path; it is not part of the ordinary child-facing flow.

### Compatibility and validation

Only clients with the same network protocol version and compatible content version may join. The host rejects extra players and joins after gameplay has advanced beyond a safe join point. Network messages use explicit size and rate limits. Only gameplay data is exchanged.

## 12. Connection Loss and Recovery

When either tablet stops receiving valid gameplay traffic, both games enter a synchronized pause. A Hebrew overlay shows reconnection progress and a countdown. The disconnected client repeatedly attempts to restore the session using its session identifier.

On successful recovery, the host sends a complete authoritative snapshot and play resumes after both clients acknowledge readiness. If recovery does not succeed within the countdown, both devices preserve progress at the latest confirmed checkpoint and return to a clear retry/menu screen.

Unexpected host termination cannot preserve the live match because the game does not implement host migration. Both devices retain the latest confirmed campaign checkpoint and can create a new session from it. Host migration is intentionally excluded from the mini-game scope.

## 13. Performance Strategy

The project is tuned for two SM-T220 tablets rather than high-end phones:

- Lightweight 2D sprites and atlases sized for the tablet display.
- Limited overdraw, dynamic lights, full-screen shaders, and transparent particles.
- Object pooling for projectiles, collectible effects, and recurring enemies.
- Fixed physics update rate selected through device profiling.
- Conservative animation frame counts and compressed audio.
- Bounded numbers of active enemies, particles, and networked objects.
- Profiling on physical SM-T220 devices throughout development.

The minimum acceptance target is stable 30 FPS during the most demanding supported scene with two connected players. Higher frame rates may be enabled only if profiling confirms stable thermal behavior.

## 14. Audio and Visual Feedback

Music is upbeat, melodic, and gentle. Each world has a distinct loop. Collectibles, checkpoints, jumps, bubbles, damage, teamwork actions, victory, and reconnection use easily distinguishable sounds.

Important events never rely on sound alone. Damage, checkpoint activation, connection state, and objectives also receive clear visual feedback. Flashing effects remain restrained and avoid rapid full-screen flashes.

## 15. Project Structure

The Godot project is divided into focused systems:

- `core`: application state, scene transitions, save data, settings, and shared constants.
- `network`: discovery, session lifecycle, protocol messages, synchronization, and reconnection.
- `player`: input, movement, abilities, health, animation, and network prediction/reconciliation.
- `world`: level rules, checkpoints, interactables, hazards, enemies, collectibles, and pooling.
- `modes`: cooperative campaign rules and the three competitive rule sets.
- `ui`: Hebrew menus, HUD, tutorial, connection overlays, and results screens.
- `audio`: music transitions, sound effects, and volume settings.
- `tests`: unit, integration, multiplayer, and performance test scenes.

Each system exposes a narrow interface and avoids direct dependencies on unrelated scenes. Network payload definitions are versioned independently from visual scene structure.

## 16. Testing Strategy

### Automated tests

- Character movement, jumps, damage, respawn, and ability rules.
- Save-data serialization and version migration.
- Competitive scoring and timers.
- Discovery packet encoding, validation, and compatibility rejection.
- Snapshot serialization and bounded input validation.
- Checkpoint and reconnection state transitions.

### Multiplayer integration tests

- Host and client discovery on the same access point.
- Repeated create/join/leave cycles.
- Simulated latency, packet loss, duplication, and reordering.
- Short Wi-Fi interruption followed by successful recovery.
- Recovery timeout and checkpoint preservation.
- Tablet sleep/wake during menus and gameplay.
- Host termination behavior.
- Rejection of mismatched protocol/content versions.

### Physical-device validation

- Complete 30–45 minute campaign sessions on both SM-T220 tablets.
- Repeated competitive rounds across all three arenas.
- Frame-time, memory, battery, and thermal observation in worst-case scenes.
- Touch-target usability with children, including accidental multi-touch.
- Hebrew right-to-left layout at the tablets' native resolution.

## 17. Acceptance Criteria

The mini-game is complete when:

1. The same signed APK installs and launches on both SM-T220 tablets.
2. A host created on one tablet is automatically discovered by the other on ordinary home Wi-Fi.
3. Both players can complete all three cooperative levels and the boss together.
4. All three competitive modes can be played and replayed without restarting the app.
5. Brief connection loss pauses and successfully restores a session, while an unrecoverable loss preserves the latest checkpoint.
6. The game remains at or above 30 FPS in profiled worst-case scenes on both tablets.
7. Menus, tutorials, connection states, and results are usable in Hebrew without adult reading during normal play.
8. No internet connection, external account, advertisement, purchase, or external server is required.
9. A full campaign and repeated competitive rounds complete without a crash, unrecoverable desynchronization, or corrupted save.

## 18. Explicitly Excluded from This Version

- Internet multiplayer or matchmaking.
- More than two simultaneous players.
- Host migration during a live match.
- Online accounts, cloud saves, leaderboards, chat, ads, or purchases.
- User-generated levels or an in-game level editor.
- Additional campaigns, characters, or cosmetic progression beyond the defined mini-game.

