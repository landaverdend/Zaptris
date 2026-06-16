extends Node3D

@onready var value: Label3D = $Value

func setup(logic: Node) -> void:
	logic.scorer.score_changed.connect(_on_score_changed)
	value.text = str(logic.scorer.score)

func _on_score_changed(new_score: int) -> void:
	value.text = str(new_score)
	value.font_size = _size(str(new_score).length())

func _size(digits: int) -> int:
	match digits:
		1, 2, 3: return 176
		4:        return 140
		5:        return 110
		6:        return 88
		_:        return 72
