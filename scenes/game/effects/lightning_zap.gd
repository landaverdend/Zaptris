extends Node3D

@onready var _bolt:   MeshInstance3D = $Bolt
@onready var _sparks: GPUParticles3D = $Sparks
var _mat: ShaderMaterial

func _ready() -> void:
	_mat = _bolt.get_active_material(0).duplicate() as ShaderMaterial
	_bolt.material_override = _mat
	_bolt.visible = false

func play() -> void:
	_bolt.visible = true
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("fade", 1.0)

	var tw := get_tree().create_tween()
	# Bolt strikes downward over 0.13s
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("progress", v),
		0.0, 1.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Impact: fire sparks the moment it hits
	tw.tween_callback(func() -> void: _sparks.restart())
	tw.tween_interval(0.06)
	# Fade bolt out
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v),
		1.0, 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _bolt.visible = false)
