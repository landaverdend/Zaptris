extends Node3D

# Three garbage-blip pips showing match progress (best of 3). Each pip is
# light gray when unwon, filling to red as that win is claimed.

const PIP_SCENE := preload("res://scenes/game/ui/garbage_block.tscn")
const PIP_COUNT  := 3
const PIP_SPACING := 0.9

const GRAY := Color(0.32, 0.32, 0.36)
const RED  := Color(1.0, 0.04, 0.02)

## Frame.tscn's backdrop is centered at local x=0.116, not 0 — match it.
const X_OFFSET := 0.116

## Overrides Frame.tscn's shared backdrop color for this instance only.
@export var backdrop_color: Color = Color(0, 0, 0, 1)

@onready var _backdrop: MeshInstance3D = $Backdrop

var _mats: Array[ShaderMaterial] = []

func setup(show: bool = false) -> void:
	visible = show
	var mat := (_backdrop.material_override as StandardMaterial3D).duplicate()
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color  = backdrop_color
	_backdrop.material_override = mat
	if _mats.is_empty():
		_build_pips()
	set_wins(0)

func set_wins(count: int) -> void:
	for i in range(_mats.size()):
		_mats[i].set_shader_parameter("fill_ratio", 1.0 if i < count else 0.0)

func _build_pips() -> void:
	var total_width := float(PIP_COUNT - 1) * PIP_SPACING
	for i in range(PIP_COUNT):
		var pip: MeshInstance3D = PIP_SCENE.instantiate()
		add_child(pip)
		pip.position = Vector3(X_OFFSET - total_width * 0.5 + i * PIP_SPACING, 0.0, 0.0)
		var mat := (pip.get_active_material(0) as ShaderMaterial).duplicate()
		mat.set_shader_parameter("color_a", GRAY)
		mat.set_shader_parameter("color_b", RED)
		pip.material_override = mat
		_mats.append(mat)
