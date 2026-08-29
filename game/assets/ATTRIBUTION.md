# Asset Attribution

The visual assets in Animal Heroes are original works created specifically for
this project. Audio authorship and licensing are unresolved pending provenance
review; see the Audio Assets section below.

## Visual Assets

All SVG artwork under `game/art/` was authored for Animal Heroes using
broad visual qualities inspired by 1990s-era cartoon platform games.
No copyrighted assets, traced images, or third-party sprites were used.

| Directory | Contents |
| --- | --- |
| `game/art/characters/` | Rabbit, fox, and robot boss illustrations |
| `game/art/collectibles/` | Star friend and checkpoint flower |
| `game/art/effects/` | Bubble ring effect |
| `game/art/environment/sunny_forest/` | Clouds, hills, foliage, flowers, mushrooms, platforms |
| `game/art/environment/crystal_caves/` | Cave background, crystal formations, stalactites, platforms |
| `game/art/environment/cloud_factory/` | Factory background, gears, metal platforms |
| `game/art/objects/` | Switches, doors, boulders, fans, conveyors, enemies, powerups, exits, walls |
| `game/art/ui/` | Jump wing, action bubble, and application icon |

## Audio Assets

The six PCM WAV files were played once in the release-candidate environment
and inspected as 16-bit mono, 22050 Hz files with non-zero sample data. Their
roles are determined by the `AudioDirector` routes below.

| File | In-game role | Repository provenance | Release status |
| --- | --- | --- | --- |
| `sunny_forest.wav` | Sunny Forest, test arena, and menu music | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |
| `crystal_caves.wav` | Crystal Caves music | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |
| `cloud_factory.wav` | Cloud Factory and robot boss music | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |
| `competition.wav` | Star Race, Treasure Dash, and Bubble Bounce music | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |
| `sfx_ui.wav` | UI interaction sound | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |
| `sfx_gameplay.wav` | Gameplay event sound | Updated in commit `5f70f72` by `Codex`; the creator and rights source are not recorded | BLOCKED pending rights provenance |

The commit author is repository provenance, not proof of authorship or a
license grant. Do not mark these WAVs releasable until their creator and
distribution rights are documented.

## License

The SVG artwork is original project artwork and is licensed under the project
license. Audio licensing remains unresolved as described above; no claim about
third-party or CC0 audio can be made from the repository history alone.
