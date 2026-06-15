extends Node

const PlayerInputScript    := preload("res://scenes/game/logic/player_input.gd")
const ControllerProfiles   := preload("res://scenes/game/logic/controller_profiles.gd")

# Fired when a new device claims an arena slot.
signal device_joined(arena_index: int, device_label: String, source: int, dev_id: int)

const GAME_ACTIONS := [
	"move_left", "move_right", "soft_drop",
	"hard_drop", "rotate_cw", "rotate_ccw", "hold"
]

# device_key (e.g. "keyboard" / "controller_0") → arena_index
var _registry: Dictionary = {}
var _arenas: Array = []
var _listening: bool = false

# ── Public API ────────────────────────────────────────────────────────────────

func start_listening(arenas: Array) -> void:
	_arenas = arenas
	_registry.clear()
	_listening = true

func stop_listening() -> void:
	_listening = false

# ── Join detection ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _listening:
		return

	var source: int = PlayerInputScript.InputSource.UNCLAIMED
	var dev_id: int = -1
	var device_key: String
	var device_label: String

	if event is InputEventKey:
		# Keyboard: only join on a real game action so typing in the name
		# field or navigating UI doesn't accidentally claim a slot.
		var is_game_action := false
		for action in GAME_ACTIONS:
			if event.is_action_pressed(action):
				is_game_action = true
				break
		if not is_game_action:
			return
		source       = PlayerInputScript.InputSource.KEYBOARD
		device_key   = "keyboard"
		device_label = "Keyboard"

	elif event is InputEventJoypadButton and event.pressed:
		# Controller: any button press joins — natural "press any button" UX.
		# Profile-specific bindings are applied after joining, so we don't
		# need game-action filtering here.
		source     = PlayerInputScript.InputSource.CONTROLLER
		dev_id     = event.device
		device_key = "controller_%d" % dev_id
		var joy_name: String = Input.get_joy_name(dev_id)
		device_label = ControllerProfiles.friendly_name(joy_name)

	else:
		return

	# Already claimed?
	if device_key in _registry:
		return

	# Find the next open arena slot
	var arena_index := _registry.size()
	if arena_index >= _arenas.size():
		return

	_registry[device_key] = arena_index

	# Apply controller-specific bindings and defaults now that we know the device.
	var arena := _arenas[arena_index] as Node3D
	var input_node := arena.get_node("PlayerInput")
	if source == PlayerInputScript.InputSource.CONTROLLER:
		_apply_bindings(dev_id)
		input_node.das_frames = ControllerProfiles.DEFAULT_CONTROLLER_DAS
		input_node.arr_frames = ControllerProfiles.DEFAULT_CONTROLLER_ARR
	input_node.configure(source, dev_id)

	emit_signal("device_joined", arena_index, device_label, source, dev_id)

	if _registry.size() >= _arenas.size():
		stop_listening()

# ── Binding application ───────────────────────────────────────────────────────

func _apply_bindings(dev_id: int) -> void:
	var joy_name: String = Input.get_joy_name(dev_id)
	var bindings: Dictionary = ControllerProfiles.get_bindings(joy_name)
	for action in bindings:
		for button in bindings[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
