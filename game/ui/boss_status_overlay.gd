class_name BossStatusOverlay
extends Control

## Read-only boss-fight status: friendly phase label, cycle progress, and a
## phase timer bar. Composed alongside GameplayHud in the robot boss arena.

const REQUIRED_CYCLES := 3
const PHASE_TIME_LIMIT := 45.0

const PHASE_LABELS := {
	"intro": "הכנה",
	"avoid": "התחמקות",
	"switches": "הפעל מתגים",
	"weak_point": "פגע בנקודה",
	"defeated": "ניצחון!",
}


func _ready() -> void:
	render("intro", 0, PHASE_TIME_LIMIT)


func render(phase: String, cycle_count: int, phase_seconds_left: float) -> void:
	$PhaseLabel.text = String(PHASE_LABELS.get(phase, phase))
	var display_cycle := mini(cycle_count + 1, REQUIRED_CYCLES) if phase != "defeated" else REQUIRED_CYCLES
	$CycleLabel.text = "%d/%d" % [display_cycle, REQUIRED_CYCLES]
	var fraction := clampf(phase_seconds_left / PHASE_TIME_LIMIT, 0.0, 1.0)
	var track: ColorRect = $TimerTrack
	var bar: ColorRect = $TimerBar
	bar.size.x = track.size.x * fraction
