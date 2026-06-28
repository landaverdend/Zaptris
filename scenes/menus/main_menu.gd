extends Control

@onready var _solo_btn: Button        = $SafeArea/MenuGrid/ActionsPanel/Actions/Solo
@onready var _multiplayer_btn: Button = $SafeArea/MenuGrid/ActionsPanel/Actions/Multiplayer
@onready var _options_btn: Button     = $SafeArea/MenuGrid/ActionsPanel/Actions/Options
@onready var _options_popup: Control  = $OptionsPopup

const _WARMUP_SHADERS := [
	"res://scenes/game/effects/hard_drop_streak.gdshader",
	"res://scenes/game/effects/line_clear.gdshader",
	"res://scenes/game/effects/lightning_flash.gdshader",
	"res://scenes/game/effects/frame_glow.gdshader",
	"res://scenes/game/effects/glow_outline.gdshader",
	"res://scenes/game/effects/danger_overlay.gdshader",
	"res://scenes/game/effects/lightning_zap.gdshader",
	"res://scenes/game/effects/garbage_cell.gdshader",
]

func _ready() -> void:
	_solo_btn.grab_focus()
	_options_popup.closed.connect(_on_options_closed)
	_warmup_shaders()

func _warmup_shaders() -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(1, 1)
	rect.position = Vector2(-9999, -9999)
	add_child(rect)
	for path in _WARMUP_SHADERS:
		var mat := ShaderMaterial.new()
		mat.shader = load(path)
		rect.material = mat
		await get_tree().process_frame
	rect.queue_free()

func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/solo/solo_mode.tscn")

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/local/local_mode.tscn")

func _on_options_pressed() -> void:
	# Disable the menu's own buttons while the popup is open — otherwise
	# d-pad navigation (which is geometry-based, not modal-aware) happily
	# jumps to whatever's focusable underneath the overlay.
	_set_menu_focusable(false)
	_options_popup.open()

func _on_options_closed() -> void:
	_set_menu_focusable(true)
	_options_btn.grab_focus()

func _set_menu_focusable(enabled: bool) -> void:
	var mode := Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	_solo_btn.focus_mode        = mode
	_multiplayer_btn.focus_mode = mode
	_options_btn.focus_mode     = mode
