class_name TouchControls
extends Control

const PlayerInputScript := preload("res://player/player_input.gd")

const LEFT := "left"
const RIGHT := "right"
const JUMP := "jump"
const ACTION := "action"

var _pointers: Dictionary = {}
var _keyboard: Dictionary = {LEFT: false, RIGHT: false, JUMP: false, ACTION: false}


func input_frame() -> PlayerInputScript.InputFrame:
	var frame = PlayerInputScript.InputFrame.new()
	var left_active := _active(LEFT)
	var right_active := _active(RIGHT)
	frame.axis = float(int(right_active) - int(left_active))
	frame.jump = _active(JUMP)
	frame.action = _active(ACTION)
	return frame


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed or touch.canceled:
			_pointers.erase(touch.index)
		else:
			_pointers[touch.index] = _action_at(touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_pointers[drag.index] = _action_at(drag.position)
	elif event is InputEventKey and not event.echo:
		_set_keyboard_key(event as InputEventKey)


func _action_at(screen_position: Vector2) -> String:
	for target in [[LEFT, $Movement/Left], [RIGHT, $Movement/Right], [JUMP, $Jump], [ACTION, $Action]]:
		if (target[1] as Control).get_global_rect().has_point(screen_position):
			return target[0]
	return ""


func _active(action: String) -> bool:
	if _keyboard.get(action, false):
		return true
	return _pointers.values().has(action)


func _set_keyboard_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_A, KEY_LEFT:
			_keyboard[LEFT] = event.pressed
		KEY_D, KEY_RIGHT:
			_keyboard[RIGHT] = event.pressed
		KEY_W, KEY_UP, KEY_SPACE:
			_keyboard[JUMP] = event.pressed
		KEY_E, KEY_ENTER:
			_keyboard[ACTION] = event.pressed
