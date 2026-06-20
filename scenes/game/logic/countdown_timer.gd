extends Control

# Shared countdown display used by SoloMode and LocalMode — instance
# countdown_display.tscn and call start() to begin. "GO!" is shown on the
# final tick, then `finished` is emitted. show_message() repurposes the same
# label for one-off announcements (e.g. "Player 1 Wins!").

signal finished

@export var duration: int = 3

@onready var _label:    Label    = $Label
@onready var _backdrop: ColorRect = $Backdrop

var _remaining: int = 0
var _tick_accum: float = 0.0
var _running: bool = false

func start() -> void:
	show()
	_backdrop.show()
	_remaining  = duration
	_tick_accum = 0.0
	_running    = true
	_label.text = str(_remaining)

func show_message(text: String) -> void:
	_running    = false
	_label.text = text
	show()
	_backdrop.show()

func stop() -> void:
	_running = false

func _process(delta: float) -> void:
	if not _running:
		return
	_tick_accum += delta
	if _tick_accum < 1.0:
		return
	_tick_accum -= 1.0
	_remaining -= 1
	if _remaining > 0:
		_label.text = str(_remaining)
	else:
		_running = false
		_label.text = "GO!"
		_backdrop.hide()
		finished.emit()
