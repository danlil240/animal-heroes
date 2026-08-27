extends SceneTree

const InputFrame := preload("res://player/player_input.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://levels/test_arena.tscn")
	if scene == null:
		_fail("the offline arena scene must exist")
		return
	var arena = scene.instantiate()
	root.add_child(arena)
	await process_frame
	await physics_frame
	if not _test_structure_and_geometry(arena):
		return
	if not _test_profiles_spawns_and_platforms(arena):
		return
	if not await _test_fall_respawn(arena):
		return
	if not _test_local_roles_and_input_delivery(arena):
		return
	if not _test_camera_and_hud_contract(arena):
		return
	if not await _test_partner_indicator(arena, Vector2i(1340, 800)):
		return
	if not await _test_partner_indicator(arena, Vector2i(1024, 600)):
		return
	quit(0)


func _test_structure_and_geometry(arena: Node) -> bool:
	for node_name in ["RabbitSpawn", "FoxSpawn", "Ground", "Checkpoint", "Collectibles", "FallRespawn", "HUD"]:
		if arena.get_node_or_null(node_name) == null:
			return _fail("missing arena node: %s" % node_name)
	if arena.get_tree().get_nodes_in_group("arena_safe_ground").size() < 1:
		return _fail("arena needs safe ground")
	if arena.get_tree().get_nodes_in_group("arena_platform").size() != 3:
		return _fail("arena needs exactly three reachable platforms")
	if arena.get_tree().get_nodes_in_group("arena_collectible").size() != 10:
		return _fail("arena needs exactly ten temporary stars")
	return true


func _test_profiles_spawns_and_platforms(arena: Node) -> bool:
	var rabbit = arena.get_node_or_null("Rabbit")
	var fox = arena.get_node_or_null("Fox")
	if rabbit == null or fox == null:
		return _fail("both hero bodies must be instantiated")
	if rabbit.profile.resource_path != "res://player/rabbit_profile.tres" or fox.profile.resource_path != "res://player/fox_profile.tres":
		return _fail("heroes must use their respective profile resources")
	if rabbit.global_position != arena.get_node("RabbitSpawn").global_position or fox.global_position != arena.get_node("FoxSpawn").global_position:
		return _fail("heroes must start at their matching spawn markers")
	for platform in arena.get_tree().get_nodes_in_group("arena_platform"):
		var horizontal_gap: float = absf(platform.global_position.x - arena.get_node("Ground").global_position.x)
		var vertical_gap: float = arena.get_node("Ground").global_position.y - platform.global_position.y
		if horizontal_gap > rabbit.profile.move_speed * 2.5 or vertical_gap > rabbit.profile.jump_speed * rabbit.profile.jump_speed / (2.0 * rabbit.gravity):
			return _fail("every platform must be reachable with the rabbit profile")
	return true


func _test_fall_respawn(arena: Node) -> bool:
	var rabbit = arena.get_node("Rabbit")
	var checkpoint: Vector2 = rabbit.checkpoint_position
	rabbit.global_position = Vector2(checkpoint.x, arena.get_node("FallRespawn").global_position.y + 40.0)
	for _tick in 60:
		await physics_frame
		if rabbit.global_position == checkpoint:
			return true
	return _fail("falling into the respawn zone must restore a hero in under two seconds")


func _test_local_roles_and_input_delivery(arena: Node) -> bool:
	var rabbit = arena.get_node("Rabbit")
	var fox = arena.get_node("Fox")
	arena.configure_local_role("rabbit")
	if not arena.get_node("Rabbit/Camera2D").enabled or not arena.get_node("Rabbit/Camera2D").is_current() or arena.get_node("Fox/Camera2D").enabled:
		return _fail("rabbit selection must make only the rabbit camera current")
	_send_key(arena.get_node("HUD/TouchControls"), KEY_D, true)
	arena.route_control_frames()
	_send_key(arena.get_node("HUD/TouchControls"), KEY_D, false)
	if rabbit.snapshot().input_axis != 1.0 or fox.snapshot().input_axis != 0.0:
		return _fail("tablet controls must deliver their frame only to the selected rabbit")
	_send_arena_key(arena, KEY_J, true)
	_send_arena_key(arena, KEY_I, true)
	_send_arena_key(arena, KEY_O, true)
	arena._physics_process(0.0)
	if fox.snapshot().input_axis != -1.0 or not fox.snapshot().jump_pressed or not fox.snapshot().action_pressed or rabbit.snapshot().input_axis != 0.0:
		return _fail("desktop secondary controls must deliver PlayerBody state only to the remote fox")
	_send_arena_key(arena, KEY_J, false)
	_send_arena_key(arena, KEY_I, false)
	_send_arena_key(arena, KEY_O, false)
	arena._physics_process(0.0)
	arena.configure_local_role("fox")
	if not arena.get_node("Fox/Camera2D").enabled or not arena.get_node("Fox/Camera2D").is_current() or arena.get_node("Rabbit/Camera2D").enabled:
		return _fail("fox selection must make only the fox camera current")
	_send_key(arena.get_node("HUD/TouchControls"), KEY_A, true)
	arena.route_control_frames()
	_send_key(arena.get_node("HUD/TouchControls"), KEY_A, false)
	if fox.snapshot().input_axis != -1.0 or rabbit.snapshot().input_axis != 0.0:
		return _fail("tablet controls must deliver their frame only to the selected fox")
	_send_arena_key(arena, KEY_L, true)
	arena._physics_process(0.0)
	if rabbit.snapshot().input_axis != 1.0 or fox.snapshot().input_axis != 0.0:
		return _fail("remote desktop delivery must swap with the selected local role")
	_send_arena_key(arena, KEY_L, false)
	return true


func _test_camera_and_hud_contract(arena: Node) -> bool:
	var hud = arena.get_node("HUD")
	if not hud is CanvasLayer or arena.get_node("HUD/TouchControls") == null or arena.get_node("HUD/PartnerIndicator") == null:
		return _fail("touch controls and indicator must live under a CanvasLayer HUD")
	for camera in [arena.get_node("Rabbit/Camera2D"), arena.get_node("Fox/Camera2D")]:
		if camera.limit_left >= camera.limit_right or camera.limit_top >= camera.limit_bottom:
			return _fail("each camera needs fixed-world limits")
	return true


func _test_partner_indicator(arena: Node, viewport_size: Vector2i) -> bool:
	root.size = viewport_size
	await process_frame
	var indicator = arena.get_node("HUD/PartnerIndicator")
	indicator.viewport_size_override = Vector2(viewport_size)
	var cases := [
		[Vector2(200, 200), Vector2(2000, 200), "right"],
		[Vector2(200, 200), Vector2(200, 2000), "bottom"],
		[Vector2(200, 200), Vector2(2000, 2000), "diagonal"],
	]
	for entry in cases:
		indicator.update_for_world_positions(entry[0], entry[1])
		if not indicator.visible or not indicator.is_on_inset_edge():
			return _fail("off-screen %s partner must intersect the inset edge" % entry[2])
		if absf(indicator.arrow.rotation - (entry[1] - entry[0]).angle()) > 0.01:
			return _fail("indicator arrow must rotate toward an off-screen %s partner" % entry[2])
		if entry[2] == "right" and not is_equal_approx(indicator.position.x, float(viewport_size.x) - indicator.inset):
			return _fail("horizontal ray must reach the right inset edge")
		if entry[2] == "bottom" and not is_equal_approx(indicator.position.y, float(viewport_size.y) - indicator.inset):
			return _fail("vertical ray must reach the bottom inset edge")
		if entry[2] == "diagonal":
			var canvas_transform := arena.get_viewport().get_canvas_transform()
			var local_screen: Vector2 = canvas_transform * entry[0]
			var partner_screen: Vector2 = canvas_transform * entry[1]
			if absf((indicator.position - local_screen).cross(partner_screen - local_screen)) > 1.0:
				return _fail("diagonal partner marker must use a ray intersection, not independent axis clamping")
	if indicator.arrow.polygon.size() != 3 or indicator.arrow.polygon[0] == indicator.arrow.polygon[1] or indicator.arrow.polygon[1] == indicator.arrow.polygon[2]:
		return _fail("indicator arrow must be visibly asymmetric geometry")
	var canvas_inverse := arena.get_viewport().get_canvas_transform().affine_inverse()
	for screen_position in [Vector2(0, 0), Vector2(viewport_size)]:
		indicator.update_for_world_positions(canvas_inverse * Vector2(300, 300), canvas_inverse * screen_position)
		if indicator.visible:
			return _fail("indicator must hide for a partner anywhere in the full viewport, including its margins")
	indicator.update_for_world_positions(Vector2(300, 300), null)
	if indicator.visible:
		return _fail("indicator must hide when the partner is unavailable")
	arena.configure_local_role("rabbit")
	arena.get_node("Rabbit").global_position = Vector2(800, 240)
	arena.get_node("Fox").global_position = Vector2(2400, 900)
	await arena.get_tree().process_frame
	indicator.update_for_world_positions(arena.get_node("Rabbit").global_position, arena.get_node("Fox").global_position)
	if not indicator.is_on_inset_edge():
		return _fail("indicator must stay in screen space after its camera canvas transform settles")
	return true


func _send_key(control: Control, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	control._input(event)


func _send_arena_key(arena: Node, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	arena._unhandled_input(event)


func _frame(axis: float, jump: bool, action: bool):
	var frame = InputFrame.InputFrame.new()
	frame.axis = axis
	frame.jump = jump
	frame.action = action
	return frame


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
