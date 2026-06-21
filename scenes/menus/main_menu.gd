extends Control

@onready var _solo_btn: Button        = $CenterContainer/VBoxContainer/Solo
@onready var _multiplayer_btn: Button = $CenterContainer/VBoxContainer/Multiplayer
@onready var _options_btn: Button     = $CenterContainer/VBoxContainer/Options
@onready var _options_popup: Control  = $OptionsPopup

func _ready() -> void:
	_solo_btn.grab_focus()
	_options_popup.closed.connect(_on_options_closed)

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
