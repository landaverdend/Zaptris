extends Node3D

# Render layer 2 = background.  ArenaLight's cull mask excludes this layer
# so it won't bleed into the background scene.
const RENDER_LAYER := 3  # bits: layer 1 + layer 2

func _ready() -> void:
	_apply_layers(self)

func _apply_layers(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = RENDER_LAYER
	for child in node.get_children():
		_apply_layers(child)
