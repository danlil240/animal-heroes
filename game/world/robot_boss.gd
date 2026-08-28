class_name RobotBoss
extends RefCounted


signal phase_changed(next_phase: String)
signal attack_telegraphed(attack_id: int)
signal switch_activated(switch_id: int)
signal weak_point_hit(weak_point_id: int)
signal defeated

const INTRO := "intro"
const AVOID := "avoid"
const SWITCHES := "switches"
const WEAK_POINT := "weak_point"
const DEFEATED := "defeated"

const PHASE_TIME_LIMIT: float = 45.0
const TELEGRAPH_DURATION: float = 0.8
const REQUIRED_CYCLES: int = 3

var phase: String = INTRO
var defeat_emissions: int = 0
var cycle_count: int = 0
var phase_timer: float = 0.0
var telegraph_timer: float = 0.0
var _active_switches: Dictionary = {}
var _hit_weak_points: Dictionary = {}
var _skip_intro: bool = false


func begin(skip_intro: bool = false) -> void:
	_skip_intro = skip_intro
	phase = INTRO
	cycle_count = 0
	phase_timer = 0.0
	telegraph_timer = 0.0
	_active_switches.clear()
	_hit_weak_points.clear()
	if skip_intro:
		_set_phase(AVOID)


func host_step(delta: float) -> void:
	var step := maxf(delta, 0.0)
	phase_timer += step
	if phase == DEFEATED:
		return
	if phase_timer >= PHASE_TIME_LIMIT:
		_fail_current_phase()
		return
	if phase == AVOID:
		telegraph_timer += step
		if telegraph_timer >= TELEGRAPH_DURATION:
			telegraph_timer = 0.0
			attack_telegraphed.emit(cycle_count)


func activate_switch(switch_id: int) -> void:
	if phase != AVOID and phase != SWITCHES:
		return
	if phase == AVOID:
		_set_phase(SWITCHES)
	_active_switches[switch_id] = true
	switch_activated.emit(switch_id)
	if _active_switches.size() >= 2:
		_set_phase(WEAK_POINT)


func hit_weak_point(weak_point_id: int) -> void:
	if phase != WEAK_POINT:
		return
	_hit_weak_points[weak_point_id] = true
	weak_point_hit.emit(weak_point_id)
	if _hit_weak_points.size() >= 2:
		cycle_count += 1
		_active_switches.clear()
		_hit_weak_points.clear()
		if cycle_count >= REQUIRED_CYCLES:
			_set_phase(DEFEATED)
			defeat_emissions += 1
			defeated.emit()
		else:
			_set_phase(AVOID)


func reset() -> void:
	phase = INTRO
	defeat_emissions = 0
	cycle_count = 0
	phase_timer = 0.0
	telegraph_timer = 0.0
	_active_switches.clear()
	_hit_weak_points.clear()


func restore_checkpoint() -> void:
	_active_switches.clear()
	_hit_weak_points.clear()
	phase_timer = 0.0
	telegraph_timer = 0.0
	_set_phase(AVOID)


func _set_phase(next_phase: String) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_timer = 0.0
	telegraph_timer = 0.0
	phase_changed.emit(next_phase)


func _fail_current_phase() -> void:
	_active_switches.clear()
	_hit_weak_points.clear()
	phase_timer = 0.0
	telegraph_timer = 0.0
	_set_phase(AVOID)
