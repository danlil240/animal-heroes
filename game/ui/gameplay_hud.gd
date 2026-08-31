class_name GameplayHud
extends Control

## Fixed tablet HUD for shared score, both heroes' health, local spread
## charges, the active combo multiplier, secret progress, and the current
## context action. Default arguments keep non-Sunny callers source-compatible.

const CONTEXT_ICONS := {
	"switch": "✿",
	"push": "↔",
	"pickup": "◯",
	"finish": "★",
	"bubble": "◯",
}

var _combo_tween: Tween


func _ready() -> void:
	$Context.visible = false
	$Ammo.visible = false
	$Power.visible = false
	$Combo.visible = false
	$Secrets.visible = false


func render(
		score: int,
		rabbit_hearts: int,
		fox_hearts: int,
		powered_charges: int = 0,
		combo_multiplier: int = 1,
		secrets_found: int = 0,
		secrets_total: int = 0,
) -> void:
	$Top/Score.text = str(maxi(score, 0))
	$Top/RabbitHearts.text = _heart_text(rabbit_hearts, 3)
	$Top/FoxHearts.text = _heart_text(fox_hearts, 4)
	# Legacy ammo dots stay for callers that only pass four args with a small
	# charge count; the spread icon/count is the primary powered indicator.
	var clamped_ammo := clampi(powered_charges, 0, 5)
	var marks: Array[Node] = $Ammo/Marks.get_children()
	for index in marks.size():
		marks[index].visible = index < clamped_ammo
	$Ammo.visible = clamped_ammo > 0 and powered_charges <= 5
	# Spread icon/count for the ten-charge powered contract.
	$Power/Count.text = str(clampi(powered_charges, 0, 99))
	$Power.visible = powered_charges > 0
	# Combo multiplier, hidden at 1x.
	if combo_multiplier > 1:
		$Combo.text = "×%d" % combo_multiplier
		$Combo.visible = true
		_play_combo_tween()
	else:
		$Combo.visible = false
	# Secret progress, always shown in Sunny Forest (0/total when none found).
	if secrets_total > 0:
		$Secrets.text = "%d/%d" % [clampi(secrets_found, 0, secrets_total), secrets_total]
		$Secrets.visible = true
	else:
		$Secrets.visible = false


func show_context(kind: String) -> void:
	if not CONTEXT_ICONS.has(kind):
		$Context.visible = false
		return
	$Context/Icon.text = String(CONTEXT_ICONS[kind])
	$Context.visible = true


func hide_context() -> void:
	$Context.visible = false


func show_score_gain(points: int, _world_position: Vector2) -> void:
	if points <= 0:
		return
	$ScoreGain.text = "+%d" % points
	$ScoreGain.visible = true
	$ScoreGain.modulate.a = 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property($ScoreGain, "position:y", $ScoreGain.position.y - 24.0, 0.45)
	tween.tween_property($ScoreGain, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback($ScoreGain.hide)


func _play_combo_tween() -> void:
	if _combo_tween != null and _combo_tween.is_running():
		return
	$Combo.scale = Vector2(1.25, 1.25)
	_combo_tween = create_tween()
	_combo_tween.tween_property($Combo, "scale", Vector2.ONE, 0.18)


func _heart_text(current: int, maximum: int) -> String:
	var clamped := clampi(current, 0, maximum)
	return "♥".repeat(clamped) + "♡".repeat(maximum - clamped)
