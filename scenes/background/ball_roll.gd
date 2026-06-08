extends Node3D

## Box boundaries (ball center stays within these)
@export var x_min: float = -22.0
@export var x_max: float = 0.0
@export var y_min: float = -10.0
@export var y_max: float = 6.0

## Speed in world units/second
@export var speed: float = 1.0

## World-space radius — used only for visual spin calculation
@export var ball_radius: float = 4.0

var _velocity: Vector2 = Vector2.ZERO
var _ball_visual: Node3D

func _ready() -> void:
	_ball_visual = get_node_or_null("Ball")

	# Start at centre of box
	position.x = (x_min + x_max) / 2.0
	position.y = (y_min + y_max) / 2.0

	# Diagonal launch so it hits both axes right away
	_velocity = Vector2(0.8, 0.6).normalized() * speed

func _process(delta: float) -> void:
	position.x += _velocity.x * delta
	position.y += _velocity.y * delta

	# Left / right walls
	if position.x <= x_min:
		position.x = x_min
		_velocity.x = abs(_velocity.x)
	elif position.x >= x_max:
		position.x = x_max
		_velocity.x = -abs(_velocity.x)

	# Floor / ceiling
	if position.y <= y_min:
		position.y = y_min
		_velocity.y = abs(_velocity.y)
	elif position.y >= y_max:
		position.y = y_max
		_velocity.y = -abs(_velocity.y)

	# Spin the visual ball based on horizontal movement
	if _ball_visual and ball_radius > 0.0:
		_ball_visual.rotate_object_local(Vector3.BACK, _velocity.x * delta / ball_radius)
