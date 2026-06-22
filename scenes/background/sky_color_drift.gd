extends WorldEnvironment

## Slowly wanders the sky shader's colors around their authored values —
## layers a few independently-phased sine waves per channel so it reads as
## organic drift rather than a mechanical pulse or loop. Stays within
## +/- drift_range of whatever top_color/bottom_color/sun_scatter are set
## to in the sky material when the scene loads.
@export var drift_speed: float = 0.25
@export var drift_range: float = 0.08
@export var phase_offset: float = 0.0

var _sky_material: ShaderMaterial
var _base_top: Color
var _base_bottom: Color
var _base_sun_scatter: Color

func _ready() -> void:
	_sky_material = environment.sky.sky_material as ShaderMaterial
	if _sky_material == null:
		return
	_base_top = _sky_material.get_shader_parameter("top_color")
	_base_bottom = _sky_material.get_shader_parameter("bottom_color")
	_base_sun_scatter = _sky_material.get_shader_parameter("sun_scatter")

func _process(_delta: float) -> void:
	if _sky_material == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + phase_offset
	_sky_material.set_shader_parameter("top_color", _drift(_base_top, t, 0.0))
	_sky_material.set_shader_parameter("bottom_color", _drift(_base_bottom, t, 2.1))
	_sky_material.set_shader_parameter("sun_scatter", _drift(_base_sun_scatter, t, 4.7))

func _drift(base: Color, t: float, phase: float) -> Color:
	var r := base.r + sin(t * drift_speed * 0.9 + phase) * drift_range
	var g := base.g + sin(t * drift_speed * 1.3 + phase + 1.0) * drift_range
	var b := base.b + sin(t * drift_speed * 1.1 + phase + 2.0) * drift_range
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), base.a)
