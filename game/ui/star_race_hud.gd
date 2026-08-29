class_name StarRaceHud
extends Control

## Friendly race HUD: per-player checkpoint progress with a finish mark.
## Read-only; never mutates race state.

const CHECKPOINTS_PER_ROUTE := 4


func render(host_progress: int, guest_progress: int, host_finished: bool, guest_finished: bool) -> void:
	$HostProgress.text = _progress_text(host_progress, host_finished)
	$GuestProgress.text = _progress_text(guest_progress, guest_finished)


func _progress_text(progress: int, finished: bool) -> String:
	var clamped := clampi(progress, 0, CHECKPOINTS_PER_ROUTE)
	var base := "%d/%d" % [clamped, CHECKPOINTS_PER_ROUTE]
	if finished:
		base += " ✓"
	return base
