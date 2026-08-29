extends SceneTree


func _init() -> void:
	var rabbit = load("res://player/rabbit_profile.tres")
	var fox = load("res://player/fox_profile.tres")
	if rabbit == null or fox == null:
		push_error("hero profile resources must exist")
		quit(1)
		return
	if rabbit.max_run_speed != 360.0 or rabbit.ground_acceleration != 1500.0 or rabbit.ground_deceleration != 1900.0 or rabbit.air_acceleration != 900.0 or rabbit.jump_cut_gravity_multiplier != 2.4 or rabbit.move_speed != rabbit.max_run_speed or rabbit.jump_speed != 580.0 or rabbit.max_hearts != 3 or rabbit.can_push_heavy:
		push_error("rabbit profile does not provide its movement and ability contract")
		quit(1)
		return
	if fox.max_run_speed != 340.0 or fox.ground_acceleration != 1400.0 or fox.ground_deceleration != 1800.0 or fox.air_acceleration != 850.0 or fox.jump_cut_gravity_multiplier != 2.4 or fox.move_speed != fox.max_run_speed or fox.jump_speed != 560.0 or fox.max_hearts != 4 or not fox.can_push_heavy:
		push_error("fox profile does not provide its movement and ability contract")
		quit(1)
		return
	quit(0)
