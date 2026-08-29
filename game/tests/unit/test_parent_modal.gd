extends SceneTree

## Tests the Hebrew parent modal update gating logic.


func _init() -> void:
	var modal_script = load("res://ui/parent_modal.gd")
	if modal_script == null:
		push_error("parent_modal script must exist")
		quit(1)
		return
	var passed := true
	passed = _test_update_blocked_during_update(modal_script) and passed
	passed = _test_update_blocked_when_pc_unavailable(modal_script) and passed
	passed = _test_update_blocked_when_not_paired(modal_script) and passed
	passed = _test_update_blocked_when_already_current(modal_script) and passed
	passed = _test_update_allowed_when_all_conditions_met(modal_script) and passed
	passed = _test_update_blocked_when_no_available_version(modal_script) and passed
	quit(0 if passed else 1)


func _make_modal(modal_script) -> Object:
	var modal = modal_script.new()
	return modal


func _test_update_blocked_during_update(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0", 1)
	modal.set_available_version("1.0.0-rc.1", 2)
	modal.set_pc_available(true)
	modal.set_paired(true)
	modal.set_update_in_progress(true)
	if modal.is_update_allowed():
		return _fail("update must be blocked during an active update")
	return true


func _test_update_blocked_when_pc_unavailable(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0", 1)
	modal.set_available_version("1.0.0-rc.1", 2)
	modal.set_pc_available(false)
	modal.set_paired(true)
	if modal.is_update_allowed():
		return _fail("update must be blocked when PC is unavailable")
	return true


func _test_update_blocked_when_not_paired(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0", 1)
	modal.set_available_version("1.0.0-rc.1", 2)
	modal.set_pc_available(true)
	modal.set_paired(false)
	if modal.is_update_allowed():
		return _fail("update must be blocked when not paired")
	return true


func _test_update_blocked_when_already_current(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0-rc.1", 2)
	modal.set_available_version("1.0.0-rc.1", 2)
	modal.set_pc_available(true)
	modal.set_paired(true)
	if modal.is_update_allowed():
		return _fail("update must be blocked when already on the available version")
	return true


func _test_update_blocked_when_no_available_version(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0", 1)
	modal.set_pc_available(true)
	modal.set_paired(true)
	if modal.is_update_allowed():
		return _fail("update must be blocked when no available version is set")
	return true


func _test_update_allowed_when_all_conditions_met(modal_script) -> bool:
	var modal = _make_modal(modal_script)
	modal.set_installed_version("1.0.0", 1)
	modal.set_available_version("1.0.0-rc.1", 2)
	modal.set_pc_available(true)
	modal.set_paired(true)
	if not modal.is_update_allowed():
		return _fail("update must be allowed when all conditions are met")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
