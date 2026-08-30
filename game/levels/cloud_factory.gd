class_name CloudFactory
extends CoopLevel

## Cooperative level 3: host-authored fan and conveyor forces feeding the boss
## entrance, with explicit entity budgets for the SM-T220 performance floor.

# Budget overrides for Cloud Factory (defaults live on CoopLevel).
func _ready() -> void:
	enemy_budget = 10
	projectile_budget = 20
	particle_budget = 64
	super._ready()

@onready var boss_entrance = $BossEntrance

var _fans: Array = []
var _conveyors: Array = []


func _setup_coop_level() -> void:
	_fans = get_tree().get_nodes_in_group("fan_zone")
	_conveyors = get_tree().get_nodes_in_group("conveyor")


func _step_level(delta: float) -> void:
	for zone in _fans:
		if zone.has_method("host_step"):
			zone.host_step(delta)
	for conveyor in _conveyors:
		if conveyor.has_method("host_step"):
			conveyor.host_step(delta)
