extends Control

# ── Quick debug tool — send garbage to P1 to test the meter and push mechanic.
# Remove or hide this node when done testing.

var _target: Node = null
var _lines: int   = 4

@onready var _lines_label: Label = $VBox/AmountRow/LinesLabel

func setup(target_logic: Node) -> void:
	_target = target_logic

func _ready() -> void:
	$VBox/AmountRow/DecButton.pressed.connect(_on_dec)
	$VBox/AmountRow/IncButton.pressed.connect(_on_inc)
	$VBox/SendButton.pressed.connect(_on_send)
	_lines_label.text = str(_lines)

func _on_dec() -> void:
	_lines = max(1, _lines - 1)
	_lines_label.text = str(_lines)

func _on_inc() -> void:
	_lines = min(20, _lines + 1)
	_lines_label.text = str(_lines)

func _on_send() -> void:
	if _target == null or not _target.garbage_enabled:
		return
	_target.receive_garbage(_lines)
