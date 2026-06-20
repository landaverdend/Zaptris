extends Light3D

## Subtle energy flicker for neon/lamp-style lights — layers two sine waves
## so it doesn't read as a perfectly periodic pulse. Optionally also sweeps
## the light's aim back and forth, like a searchlight scanning a surface
## (leave sweep_amount_deg at 0 to disable).
@export var flicker_speed: float = 9.0
@export var flicker_amount: float = 0.15  # fraction of base energy, +/-
@export var phase_offset: float = 0.0     # stagger multiple lights so they don't sync

@export var sweep_speed: float = 0.4
@export var sweep_amount_deg: float = 0.0
@export var sweep_axis: Vector3 = Vector3.UP

var _base_energy: float
var _base_transform: Transform3D

func _ready() -> void:
	_base_energy = light_energy
	_base_transform = transform

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + phase_offset
	var f := sin(t * flicker_speed) * 0.6 + sin(t * flicker_speed * 2.7 + 1.3) * 0.4
	light_energy = _base_energy * (1.0 + flicker_amount * f)

	if sweep_amount_deg != 0.0:
		var angle := deg_to_rad(sweep_amount_deg) * sin(t * sweep_speed)
		transform = _base_transform.rotated_local(sweep_axis.normalized(), angle)
