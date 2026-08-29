class_name InputTimeline
extends RefCounted

const PlayerInputScript := preload("res://player/player_input.gd")

var _hint_frames: int = 0
var _entries: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _assertions: Array[Dictionary] = []

func _init(total_frames_hint: int = 0) -> void:
	_hint_frames = maxi(total_frames_hint, 0)

func add(peer_id: int, start_frame: int, end_frame: int, input: Dictionary) -> void:
	_entries.append({"peer_id": peer_id, "start": start_frame, "end": end_frame, "input": input})

func capture(frame: int, name: String) -> void:
	_captures.append({"frame": frame, "name": name})

func assert_at(frame: int, kind: String, args: Array) -> void:
	_assertions.append({"frame": frame, "kind": kind, "args": args})

func assert_end(kind: String, args: Array = []) -> void:
	_assertions.append({"kind": kind, "args": args})

func total_frames() -> int:
	var max_frame := _hint_frames
	for c in _captures:
		max_frame = maxi(max_frame, int(c.frame))
	for a in _assertions:
		if a.has("frame"):
			max_frame = maxi(max_frame, int(a.frame))
	return max_frame

func frame_for(peer_id: int, frame: int) -> PlayerInputScript.InputFrame:
	var out := PlayerInputScript.InputFrame.new()
	var latest_axis: float = 0.0
	var have_axis := false
	for e in _entries:
		if int(e.peer_id) != peer_id:
			continue
		if frame < int(e.start) or frame > int(e.end):
			continue
		var input: Dictionary = e.input
		if input.has("axis"):
			latest_axis = float(input.axis)
			have_axis = true
		if input.has("jump") and bool(input.jump):
			out.jump = true
		if input.has("action") and bool(input.action):
			out.action = true
	out.axis = latest_axis if have_axis else 0.0
	return out

func captures() -> Array[Dictionary]:
	return _captures

func assertions() -> Array[Dictionary]:
	return _assertions
