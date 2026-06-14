extends Node3D

@onready var score_value: Label3D = $ScoreBox/Value
@onready var lines_value: Label3D = $Lines/Value
@onready var level_value: Label3D = $Lines/Level/Value
@onready var level_box:   Node3D  = $Lines/Level
@onready var sats_value:  Label3D = $SatsWon/Value

var _logic: Node
var _sats_won: int = 0

func setup(logic: Node, show_level: bool = true, show_sats: bool = false) -> void:
	_logic = logic
	_logic.scorer.score_changed.connect(_on_score_changed)
	_logic.lines_cleared.connect(_on_lines_cleared)
	_logic.level_changed.connect(_on_level_changed)
	score_value.text = "0"
	lines_value.text = "0"
	level_value.text = "1"
	level_box.visible = show_level
	_sats_won = 0
	sats_value.text        = "0"
	$SatsWon.visible       = show_sats

func add_sats(amount: int) -> void:
	_sats_won += amount
	sats_value.text = str(_sats_won)

func _on_score_changed(new_score: int) -> void:
	score_value.text = str(new_score)
	score_value.font_size = _font_size_for_digits(str(new_score).length())

func _on_lines_cleared(_n: int) -> void:
	lines_value.text = str(_logic.total_lines)
	lines_value.font_size = _font_size_for_digits(str(_logic.total_lines).length())

func _on_level_changed(new_level: int) -> void:
	level_value.text = str(new_level)

func _font_size_for_digits(digits: int) -> int:
	match digits:
		1, 2, 3: return 176
		4:        return 140
		5:        return 110
		6:        return 88
		_:        return 72
