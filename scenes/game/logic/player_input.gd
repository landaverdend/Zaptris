class_name PlayerInput extends Node

enum InputSource { UNCLAIMED, KEYBOARD, CONTROLLER, ANY }

# Set via configure() — not exported since InputRouter owns assignment.
var input_source: InputSource = InputSource.UNCLAIMED
var device_id: int = -1

@export var das_frames: float = 12.0  # frames before repeat starts
@export var arr_frames: float = 2.0   # frames per repeat step

@onready var logic: Node = $"../GameLogic"

var _held: Dictionary = {}
var _last_horizontal: String = ""

const HORIZONTAL = ["move_left", "move_right"]

# Called by InputRouter (local) or SoloMode (solo) to bind a device.
func configure(source: InputSource, dev_id: int = -1) -> void:
	input_source = source
	device_id    = dev_id

# Flush any held inputs. Call this before starting a new round so keys
# physically held at round-end don't carry over to the next spawn.
func clear_held() -> void:
	_held.clear()
	_last_horizontal = ""

# ── Per-frame DAS/ARR tick ────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if input_source == InputSource.UNCLAIMED:
		return
	if logic.active_piece == null:
		return

	# Soft drop: fires every frame while held, no DAS delay.
	if _held.has("soft_drop"):
		logic.soft_drop()

	# DAS/ARR for horizontal movement only.
	for action in HORIZONTAL:
		if not _held.has(action):
			continue
		var held = _held[action]
		held["frames"] += 1
		if held["frames"] < das_frames:
			continue
		held["arr_counter"] += 1
		if arr_frames == 0 or held["arr_counter"] >= arr_frames:
			held["arr_counter"] = 0
			_dispatch(action)

# ── Input events ──────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if input_source == InputSource.UNCLAIMED:
		return
	if logic.active_piece == null:
		return

	# OS key-repeat events would reset the DAS counter mid-charge — filter them.
	if event is InputEventKey and event.echo:
		return

	# Filter by source — keyboard and controller 0 both have device=0,
	# so we separate them by event type rather than device ID alone.
	match input_source:
		InputSource.KEYBOARD:
			if not event is InputEventKey:
				return
		InputSource.CONTROLLER:
			if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
				return
			if event.device != device_id:
				return
		InputSource.ANY:
			pass

	# One-shot actions
	if event.is_action_pressed("hard_drop"):
		logic.hard_drop()
		return
	if event.is_action_pressed("rotate_cw"):
		logic.try_rotate(1)
		return
	if event.is_action_pressed("rotate_ccw"):
		logic.try_rotate(-1)
		return
	if event.is_action_pressed("hold"):
		logic.hold()
		return

	# Soft drop: just track press/release; _physics_process fires it every frame.
	if event.is_action_pressed("soft_drop"):
		_held["soft_drop"] = {}
		return
	if event.is_action_released("soft_drop"):
		_held.erase("soft_drop")
		return

	# Horizontal movement with DAS/ARR
	for action in HORIZONTAL:
		if event.is_action_pressed(action):
			_last_horizontal = action
			_dispatch(action)
			_held[action] = {"frames": 0.0, "arr_counter": 0.0}
		elif event.is_action_released(action):
			_held.erase(action)
			if action == _last_horizontal:
				if action == "move_left" and "move_right" in _held:
					_last_horizontal = "move_right"
				elif action == "move_right" and "move_left" in _held:
					_last_horizontal = "move_left"
				else:
					_last_horizontal = ""

# ── Action dispatch ───────────────────────────────────────────────────────────

func _dispatch(action: String) -> void:
	if action == "move_left" or action == "move_right":
		if action != _last_horizontal:
			return
	match action:
		"move_left":
			logic.try_move(0, -1)
		"move_right":
			logic.try_move(0, 1)
