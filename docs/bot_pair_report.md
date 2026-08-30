# Bot Pair Gameplay Report

Generated: `2026-08-29T21:38:08Z`  
Harness: `game/tests/integration/test_bot_pair.gd`  
Frames per level: `1800` (~60s at 30 physics fps)  
Godot: `godot`  

## sunny_forest

- exit code: `0`
- engine errors: `2`  |  warnings: `1`
- report: `BOT_REPORT level=sunny_forest frames_run=1800 frames_requested=1800 finished=false team_score=100 stars=0 enemies_remaining=4 hearts_rabbit=3 hearts_fox=4 min_hearts_rabbit=3 min_hearts_fox=4 grants=5 max_active_bubbles=6 active_bubbles=6 pool_exhausted=true rabbit_pos=(321,655) fox_pos=(353,655)`

## crystal_caves

- exit code: `0`
- engine errors: `1`  |  warnings: `1`
- report: `BOT_REPORT level=crystal_caves frames_run=1800 frames_requested=1800 finished=false team_score=0 stars=0 enemies_remaining=0 hearts_rabbit=3 hearts_fox=4 min_hearts_rabbit=3 min_hearts_fox=4 grants=0 max_active_bubbles=0 active_bubbles=0 pool_exhausted=false rabbit_pos=(-179,1779537) fox_pos=(-145,1405224)`

## cloud_factory

- exit code: `0`
- engine errors: `1`  |  warnings: `1`
- report: `BOT_REPORT level=cloud_factory frames_run=1800 frames_requested=1800 finished=false team_score=0 stars=0 enemies_remaining=0 hearts_rabbit=3 hearts_fox=4 min_hearts_rabbit=3 min_hearts_fox=4 grants=0 max_active_bubbles=0 active_bubbles=0 pool_exhausted=false rabbit_pos=(3048,655) fox_pos=(3046,607)`

## Aggregated Error Signatures

Total engine errors across levels: `4`  |  warnings: `3`

| count | levels | signature |
|------:|--------|-----------|
| 3 | sunny_forest,crystal_caves,cloud_factory | `ERROR: N resources still in use at exit (run with --verbose for details).` |
| 1 | sunny_forest | `Sunny Forest bubble pool exhausted; shot sequence rejected` |

