extends Node3D

## How tall the bolt is, in world units, measured up from this node's origin
## (the impact point). The node's own Position is where it strikes — move it
## in the 3D viewport or Inspector to retarget.
@export var bolt_height: float = 6.0
## Bolt width, in world units.
@export var bolt_width: float = 1.5
## Color of the bolt and its impact sparks.
@export var bolt_color: Color = Color(1.0, 0.55, 0.05)

@onready var _bolt:   MeshInstance3D = $Bolt
@onready var _sparks: GPUParticles3D = $Sparks
@onready var _flash:  MeshInstance3D = $Flash
var _mat: ShaderMaterial
var _flash_mat: ShaderMaterial

func _ready() -> void:
	_mat = _bolt.get_active_material(0).duplicate() as ShaderMaterial
	_bolt.material_override = _mat
	_bolt.visible = false
	_mat.set_shader_parameter("bolt_color", bolt_color)

	# Duplicate the mesh too — it's shared across instances of this scene,
	# so mutating it directly would make every zap share one size.
	var quad := (_bolt.mesh as QuadMesh).duplicate() as QuadMesh
	quad.material = _mat
	quad.size = Vector2(bolt_width, bolt_height)
	_bolt.mesh = quad
	_bolt.position.y = bolt_height * 0.5  # keep the bottom edge anchored at this node's origin

	# Sparks: duplicate their resources too, then recolor from bolt_color.
	var spark_mesh := (_sparks.draw_pass_1 as QuadMesh).duplicate() as QuadMesh
	var spark_mat := (spark_mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	spark_mat.albedo_color = bolt_color.lightened(0.5)
	spark_mat.emission     = bolt_color
	spark_mesh.material    = spark_mat
	_sparks.draw_pass_1     = spark_mesh

	var process_mat := (_sparks.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	var grad := Gradient.new()
	grad.set_color(0, bolt_color.lightened(0.6))
	grad.set_color(1, Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient        = grad
	process_mat.color_ramp   = grad_tex
	_sparks.process_material = process_mat

	# Flash: same duplicate-per-instance treatment.
	_flash_mat = (_flash.get_active_material(0)).duplicate() as ShaderMaterial
	_flash_mat.set_shader_parameter("flash_color", bolt_color.lightened(0.5))
	var flash_mesh := (_flash.mesh as QuadMesh).duplicate() as QuadMesh
	flash_mesh.material = _flash_mat
	_flash.mesh = flash_mesh
	_flash.visible = false

func play() -> void:
	_bolt.visible = true
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("fade", 1.0)

	var tw := get_tree().create_tween()
	# Bolt strikes downward over 0.13s
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("progress", v),
		0.0, 1.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Impact: fire sparks and a bright burst flash the moment it hits
	tw.tween_callback(func() -> void: _impact())
	tw.tween_interval(0.06)
	# Fade bolt out
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v),
		1.0, 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _bolt.visible = false)

func _impact() -> void:
	_sparks.restart()

	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.2
	_flash_mat.set_shader_parameter("intensity", 1.0)

	var ftw := get_tree().create_tween()
	ftw.set_parallel(true)
	ftw.tween_property(_flash, "scale", Vector3.ONE * (bolt_width * 2.2 + 0.5), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ftw.tween_method(func(v: float) -> void: _flash_mat.set_shader_parameter("intensity", v),
		1.0, 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ftw.chain().tween_callback(func() -> void: _flash.visible = false)
