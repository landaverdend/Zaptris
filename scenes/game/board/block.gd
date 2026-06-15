extends Node3D

# MeshInstance3D lives inside the instanced GLB at a known path.
# If you rename the mesh object in Blender, update this line.
@onready var mesh_instance: MeshInstance3D = $BlockMesh/Cube

# Called once after instantiation to set this block's piece color.
# Creates a unique material per block so each can have its own color
# without affecting others.
# Pass ghost = true for the drop-preview: same color, semi-transparent.
const EMISSION_ENERGY : float = 0.2  # tweak: higher = more bloom

func set_color(color: Color, ghost: bool = false) -> void:
	if mesh_instance == null:
		return
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.4
	mat.metallic = 0.1
	if ghost:
		mat.albedo_color = Color(color.r, color.g, color.b, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = EMISSION_ENERGY
	mesh_instance.material_override = mat
