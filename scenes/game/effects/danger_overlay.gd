extends Node3D

@onready var _mesh:      MeshInstance3D = $Mesh
@onready var _particles: GPUParticles3D = $Particles

var _mat:   ShaderMaterial
var _tween: Tween

func _ready() -> void:
	_mat = _mesh.material_override as ShaderMaterial
	_mat.set_shader_parameter("danger", 0.0)

func activate(active: bool) -> void:
	if active:
		show()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var from := float(_mat.get_shader_parameter("danger"))
	_tween.tween_method(
		func(v: float): _mat.set_shader_parameter("danger", v),
		from, 1.0 if active else 0.0, 0.35
	)
	if not active:
		_tween.tween_callback(hide)
	_particles.emitting = active
