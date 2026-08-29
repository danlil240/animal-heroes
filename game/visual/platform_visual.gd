class_name PlatformVisual
extends Node2D

@export var ground_variant: bool = false


func _ready() -> void:
	$Ground.visible = ground_variant
	$Small.visible = not ground_variant
	cover_collision_surface()


## Stretches the artwork so it is never narrower than the collider it decorates.
## The ground colliders run from 1600 up to 3400 px wide while the ground art is
## a fixed 1600 px, so without this the heroes stand and walk on invisible ground
## everywhere outside the middle of the level.
func cover_collision_surface() -> void:
	var sprite: Sprite2D = $Ground if ground_variant else $Small
	if sprite.texture == null:
		return
	var surface_width := _collision_surface_width()
	if surface_width <= 0.0:
		return
	# Only ever widen: the small platform art is authored to overhang its
	# collider slightly, and that shaping must survive.
	sprite.scale.x = maxf(1.0, surface_width / float(sprite.texture.get_width()))


func _collision_surface_width() -> float:
	var body := get_parent()
	if body == null:
		return 0.0
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			return ((child as CollisionShape2D).shape as RectangleShape2D).size.x
	return 0.0
