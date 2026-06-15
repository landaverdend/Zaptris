extends Node3D

@onready var sprite: Sprite3D = $Sprite

func set_color(color: Color, ghost: bool = false) -> void:
	sprite.transparent = ghost
	sprite.modulate = Color(color.r, color.g, color.b, 0.3 if ghost else 1.0)
