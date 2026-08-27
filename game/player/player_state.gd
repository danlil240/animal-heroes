class_name PlayerState
extends RefCounted

var peer_id: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var hearts: int = 0
var max_hearts: int = 0
var can_push_heavy: bool = false
var grounded: bool = false
var input_axis: float = 0.0
var jump_pressed: bool = false
var action_pressed: bool = false
var action_buffered: bool = false
var jump_buffer_remaining: float = 0.0
var coyote_remaining: float = 0.0
var damage_cooldown_remaining: float = 0.0
var checkpoint_position: Vector2 = Vector2.ZERO
var last_damage_source_peer_id: int = 0


func to_dictionary() -> Dictionary:
	return {
		"peer_id": peer_id,
		"position": position,
		"velocity": velocity,
		"hearts": hearts,
		"max_hearts": max_hearts,
		"can_push_heavy": can_push_heavy,
		"grounded": grounded,
		"input_axis": input_axis,
		"jump_pressed": jump_pressed,
		"action_pressed": action_pressed,
		"action_buffered": action_buffered,
		"jump_buffer_remaining": jump_buffer_remaining,
		"coyote_remaining": coyote_remaining,
		"damage_cooldown_remaining": damage_cooldown_remaining,
		"checkpoint_position": checkpoint_position,
		"last_damage_source_peer_id": last_damage_source_peer_id,
	}
