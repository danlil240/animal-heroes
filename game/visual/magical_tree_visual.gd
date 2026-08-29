class_name MagicalTreeVisual
extends Node2D

var _elapsed: float = 0.0
var _celebrating: bool = false


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	$Tree.rotation = sin(_elapsed * 1.4) * 0.008
	$Glow.modulate.a = 0.28 + sin(_elapsed * 2.7) * 0.08
	if _celebrating:
		$Stars.rotation += delta * 0.8


func play_celebration() -> void:
	_celebrating = true
	$Stars.visible = true
	var tween := create_tween().set_loops(3)
	tween.tween_property($Stars, "scale", Vector2(1.12, 1.12), 0.2)
	tween.tween_property($Stars, "scale", Vector2.ONE, 0.2)
