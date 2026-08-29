class_name PlayerProfile
extends Resource

## Compatibility alias for callers that need the hero's full horizontal speed.
@export var move_speed: float = 340.0
@export var max_run_speed: float = 340.0
@export var ground_acceleration: float = 1400.0
@export var ground_deceleration: float = 1800.0
@export var air_acceleration: float = 850.0
@export var jump_cut_gravity_multiplier: float = 2.4
@export var jump_speed: float = 420.0
@export var max_hearts: int = 3
@export var can_push_heavy: bool = false
