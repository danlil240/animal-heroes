extends SceneTree

var _failed: bool = false


func _init() -> void:
	_test_combo_chain_caps_and_expires()
	if _failed:
		quit(1)
		return
	_test_combo_refresh_only_extends_active_chain()
	if _failed:
		quit(1)
		return
	_test_combo_snapshot_round_trip()
	if _failed:
		quit(1)
		return
	_test_team_score_applies_bounded_multipliers_and_secret_value()
	quit(1 if _failed else 0)


## Catches the first score being multiplied, a chain skipping multipliers, or
## the active multiplier surviving beyond the 2.5-second scoring window.
func _test_combo_chain_caps_and_expires() -> void:
	var combo_script = load("res://core/team_combo.gd")
	if combo_script == null:
		_fail("team combo rules must exist")
		return
	var combo = combo_script.new()
	if combo.preview_multiplier() != 1:
		_fail("first event must score at 1x")
		return
	combo.commit_scored_event()
	if combo.preview_multiplier() != 2:
		_fail("second chained event must score at 2x")
		return
	combo.commit_scored_event()
	combo.commit_scored_event()
	combo.commit_scored_event()
	if combo.multiplier != 4:
		_fail("combo must cap at 4x")
		return
	combo.step(2.51)
	if combo.multiplier != 1 or combo.remaining != 0.0:
		_fail("combo must expire after 2.5 seconds")


## Catches teamwork starting a chain or failing to refresh one already active.
func _test_combo_refresh_only_extends_active_chain() -> void:
	var combo_script = load("res://core/team_combo.gd")
	if combo_script == null:
		_fail("team combo rules must exist")
		return
	var combo = combo_script.new()
	combo.refresh()
	if combo.remaining != 0.0 or combo.preview_multiplier() != 1:
		_fail("refresh must not activate an idle combo")
		return
	combo.commit_scored_event()
	combo.step(1.5)
	combo.refresh()
	combo.step(1.25)
	if combo.remaining <= 0.0 or combo.preview_multiplier() != 2:
		_fail("refresh must extend an active combo without advancing it")


## Catches reconnect restoration dropping or accepting invalid combo state.
func _test_combo_snapshot_round_trip() -> void:
	var combo_script = load("res://core/team_combo.gd")
	if combo_script == null:
		_fail("team combo rules must exist")
		return
	var original = combo_script.new()
	original.commit_scored_event()
	original.commit_scored_event()
	original.step(0.75)
	var restored = combo_script.new()
	if not restored.restore(original.snapshot()):
		_fail("valid combo snapshot must restore")
		return
	if restored.multiplier != 2 or not is_equal_approx(restored.remaining, 1.75):
		_fail("combo snapshot must preserve multiplier and remaining window")
		return
	var before: Dictionary = restored.snapshot()
	if restored.restore({"multiplier": 5, "remaining": 1.0}):
		_fail("combo restore must reject multipliers above the cap")
		return
	if restored.snapshot() != before:
		_fail("failed combo restore must preserve existing state")


## Catches callers bypassing multiplier bounds or omitting secret scoring.
func _test_team_score_applies_bounded_multipliers_and_secret_value() -> void:
	var score = load("res://core/team_score.gd").new()
	if score.award("star:one", "star", 0) != 10:
		_fail("score multipliers below one must clamp to 1x")
		return
	if score.award("enemy:one", "enemy", 3) != 75:
		_fail("enemy score must apply the requested multiplier")
		return
	if score.award("secret:one", "secret", 8) != 400:
		_fail("secret score must be 100 points with a maximum 4x multiplier")
		return
	if score.award("secret:one", "secret", 4) != 0 or score.total != 485:
		_fail("multiplied scores must retain duplicate-event protection")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
