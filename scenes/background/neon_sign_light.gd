extends Light3D

## Makes a single light read as an active neon sign rather than ambient
## lighting: a snappier on/off-feeling blink layered on top of a slow
## color drift between two hues.
@export var base_color: Color = Color(0.4706, 0.1765, 0.2)
@export var accent_color: Color = Color(1.0, 0.32, 0.05)
@export var color_drift_speed: float = 0.6
@export var blink_speed: float = 11.0
@export var blink_amount: float = 0.3

var _base_energy: float

func _ready() -> void:
	_base_energy = light_energy

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var blink := sin(t * blink_speed) * 0.6 + sin(t * blink_speed * 2.3 + 0.7) * 0.4
	light_energy = _base_energy * (1.0 + blink_amount * blink)

	var drift := sin(t * color_drift_speed) * 0.5 + 0.5
	light_color = base_color.lerp(accent_color, drift)
