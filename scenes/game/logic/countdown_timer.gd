extends Node

# Shared countdown node used by SoloMode and LocalMode.
# Call start(label) to begin. The label is updated each second.
# "GO!" is shown on the final tick, then `finished` is emitted.

signal finished

@export var duration: int = 3

var _label: Label = null
var _remaining: int = 0
var _tick_accum: float = 0.0
var _running: bool = false

func start(label: Label) -> void:
	_label     = label
	_remaining = duration
	_tick_accum = 0.0
	_running   = true
	_label.text = str(_remaining)

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
		finished.emit()
