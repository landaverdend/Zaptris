extends Node3D

@onready var value: Label3D = $Value
var _logic: Node

func setup(logic: Node) -> void:
	_logic = logic
	logic.lines_cleared.connect(_on_lines_cleared)
	value.text = "0"

func _on_lines_cleared(_n: int) -> void:
	value.text = str(_logic.total_lines)
	value.font_size = _size(str(_logic.total_lines).length())

func _size(digits: int) -> int:
	match digits:
		1, 2, 3: return 176
		4:        return 140
		5:        return 110
		6:        return 88
		_:        return 72
