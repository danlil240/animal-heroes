extends SceneTree


func _init() -> void:
	var rabbit = load("res://player/rabbit_profile.tres")
	var fox = load("res://player/fox_profile.tres")
	if rabbit == null or fox == null:
		push_error("hero profile resources must exist")
		quit(1)
		return
	if rabbit.move_speed != 240.0 or rabbit.jump_speed != 440.0 or rabbit.max_hearts != 3 or rabbit.can_push_heavy:
		push_error("rabbit profile does not provide its movement and ability contract")
		quit(1)
		return
	if fox.move_speed != 220.0 or fox.jump_speed != 410.0 or fox.max_hearts != 4 or not fox.can_push_heavy:
		push_error("fox profile does not provide its movement and ability contract")
		quit(1)
		return
	quit(0)
