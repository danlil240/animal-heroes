class_name BubbleBounceHud
extends Control

## Friendly bubble match HUD: countdown timer, per-player scores, and the
## local player's bubble ammo. Read-only; never mutates match state.


func _ready() -> void:
	$Ammo.visible = false


func render(time_remaining: float, host_score: int, guest_score: int, local_ammo: int) -> void:
	$Timer.text = _format_time(time_remaining)
	$HostScore.text = str(maxi(host_score, 0))
	$GuestScore.text = str(maxi(guest_score, 0))
	var clamped_ammo := clampi(local_ammo, 0, 5)
	var marks: Array[Node] = $Ammo/Marks.get_children()
	for index in marks.size():
		marks[index].visible = index < clamped_ammo
	$Ammo.visible = clamped_ammo > 0


func _format_time(seconds: float) -> String:
	var total := maxi(int(roundf(seconds)), 0)
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]
