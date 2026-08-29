class_name RobotBossArena
extends CoopLevel

## Cooperative boss arena: the comical robot's deterministic phase machine runs
## on the host tick, and defeating it completes the campaign.

const RobotBoss = preload("res://world/robot_boss.gd")

var boss: RobotBoss = null

@onready var _boss_overlay = $HUD/BossStatusOverlay


func _setup_coop_level() -> void:
	boss = RobotBoss.new()
	boss.begin(true)
	boss.defeated.connect(_on_boss_defeated)


func _step_level(delta: float) -> void:
	boss.host_step(delta)
	_boss_overlay.render(boss.phase, boss.cycle_count, RobotBoss.PHASE_TIME_LIMIT - boss.phase_timer)


func activate_switch(switch_id: int) -> void:
	boss.activate_switch(switch_id)


func hit_weak_point(weak_point_id: int) -> void:
	boss.hit_weak_point(weak_point_id)


func _on_boss_defeated() -> void:
	coop_mode.complete_campaign()
