class_name GameplayHud
extends Control

## Fixed tablet HUD for shared score, both heroes' health, local bubble ammo,
## and the current context action.

const CONTEXT_ICONS := {
	"switch": "✿",
	"push": "↔",
	"pickup": "◯",
	"finish": "★",
}


func _ready() -> void:
	$Context.visible = false
	$Ammo.visible = false


func render(score: int, rabbit_hearts: int, fox_hearts: int, local_ammo: int) -> void:
	$Top/Score.text = str(maxi(score, 0))
	$Top/RabbitHearts.text = _heart_text(rabbit_hearts, 3)
	$Top/FoxHearts.text = _heart_text(fox_hearts, 4)
	var clamped_ammo := clampi(local_ammo, 0, 5)
	var marks: Array[Node] = $Ammo/Marks.get_children()
	for index in marks.size():
		marks[index].visible = index < clamped_ammo
	$Ammo.visible = clamped_ammo > 0


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


func _heart_text(current: int, maximum: int) -> String:
	var clamped := clampi(current, 0, maximum)
	return "♥".repeat(clamped) + "♡".repeat(maximum - clamped)
