extends Control

## Generic controller-navigable on-screen keyboard. Reusable anywhere a
## LineEdit needs text entry from a gamepad — call open(line_edit) to start
## editing it, close() (or the Done key) to finish. Navigation between keys
## relies on Godot's built-in directional focus traversal (ui_up/down/left/
## right/accept), which already responds to the d-pad by default.

signal closed

const ControllerProfiles := preload("res://scenes/game/logic/controller_profiles.gd")

const KEY_ROWS := [
	"1234567890",
	"qwertyuiop",
	"asdfghjkl@",
	"zxcvbnm.-_",
]

const FONT := preload("res://assets/ui/fonts/Orbitron/static/Orbitron-Bold.ttf")

@onready var _grid:          GridContainer = $VBox/Grid
@onready var _backspace_btn: Button        = $VBox/Actions/Backspace
@onready var _done_btn:      Button        = $VBox/Actions/Done

var _target: LineEdit = null

# The target LineEdit never has real Godot focus while we're open (focus has
# to stay on the key grid for d-pad nav), so its native caret never draws.
# This is a hand-drawn stand-in, positioned by measuring text width directly.
var _caret: ColorRect
var _blink_timer: Timer

func _ready() -> void:
	for row in KEY_ROWS:
		for ch in row:
			var btn := Button.new()
			btn.text = ch
			btn.focus_mode = Control.FOCUS_ALL
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_override("font", FONT)
			btn.pressed.connect(_on_key_pressed.bind(ch))
			_grid.add_child(btn)
	_backspace_btn.pressed.connect(_on_backspace_pressed)
	_done_btn.pressed.connect(_on_done_pressed)

	_caret = ColorRect.new()
	_caret.color = Color(1, 1, 1, 1)
	_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blink_timer = Timer.new()
	_blink_timer.wait_time = 0.5
	_blink_timer.timeout.connect(func(): _caret.visible = not _caret.visible)
	add_child(_blink_timer)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if _is_decline_press(event):
		_on_backspace_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_move_caret(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_move_caret(1)
			get_viewport().set_input_as_handled()

# The natural "B"/decline face button — physical position differs by
# controller (Switch's printed B is Godot's JOY_BUTTON_A; everyone else's
# printed B is JOY_BUTTON_B), so pick per-device the same way the rest of
# the project already does for face-button mismatches.
func _is_decline_press(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return false
	var joy_name := Input.get_joy_name(event.device)
	var decline_button := JOY_BUTTON_A if ControllerProfiles._is_switch(joy_name) else JOY_BUTTON_B
	return event.button_index == decline_button

func _move_caret(delta: int) -> void:
	if _target == null:
		return
	_target.caret_column = clampi(_target.caret_column + delta, 0, _target.text.length())
	_update_caret_visual()

func _update_caret_visual() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var font: Font = _target.get_theme_font("font")
	if font == null:
		font = FONT
	var font_size := _target.get_theme_font_size("font_size")
	var full_text := _target.text
	var before := full_text.substr(0, _target.caret_column)
	var full_w   := font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var before_w := font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_h   := font.get_height(font_size)
	var text_start_x: float = (_target.size.x - full_w) * 0.5  # field text is center-aligned
	_caret.position = Vector2(text_start_x + before_w, (_target.size.y - text_h) * 0.5)
	_caret.size = Vector2(2, text_h)
	_caret.visible = true
	_blink_timer.start()  # reset phase so it's always visible right after an edit

func open(target: LineEdit) -> void:
	_target = target
	# Drop in below the field rather than covering it — sized independently
	# of whatever container holds us, so it can spill past a narrow parent
	# (e.g. the lobby card) into the surrounding arena area if it needs to.
	var field_rect := target.get_global_rect()
	global_position = Vector2(
		field_rect.position.x + field_rect.size.x * 0.5 - size.x * 0.5,
		field_rect.position.y + field_rect.size.y + 8.0
	)
	show()
	target.add_child(_caret)
	_update_caret_visual()
	var first_key := _grid.get_child(0) as Button
	if first_key:
		first_key.grab_focus()

func close() -> void:
	hide()
	_blink_timer.stop()
	if _caret.get_parent():
		_caret.get_parent().remove_child(_caret)
	_target = null
	closed.emit()

func _on_key_pressed(ch: String) -> void:
	if _target == null:
		return
	var col := _target.caret_column
	_target.text = _target.text.insert(col, ch)
	_target.caret_column = col + 1
	_update_caret_visual()

func _on_backspace_pressed() -> void:
	if _target == null or _target.caret_column <= 0:
		return
	var col := _target.caret_column
	_target.text = _target.text.left(col - 1) + _target.text.substr(col)
	_target.caret_column = col - 1
	_update_caret_visual()

func _on_done_pressed() -> void:
	close()
