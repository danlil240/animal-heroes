class_name TreasureDashHud
extends Control

## Timed collection match HUD: countdown timer and per-player scores.
## Read-only; never mutates match state.


func render(time_remaining: float, host_score: int, guest_score: int) -> void:
	$Timer.text = _format_time(time_remaining)
	$HostScore.text = str(maxi(host_score, 0))
	$GuestScore.text = str(maxi(guest_score, 0))


func _format_time(seconds: float) -> String:
	var total := maxi(int(roundf(seconds)), 0)
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]
