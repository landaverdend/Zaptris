extends Control

@onready var score_label: Label = $VBoxContainer/ScoreLabel
@onready var lines_label: Label = $VBoxContainer/LinesLabel
@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var combo_label: Label = $VBoxContainer/ComboLabel
@onready var logic: Node = $"../../GameLogic"

func _ready() -> void:
	logic.scorer.score_changed.connect(_on_score_changed)
	logic.scorer.clear_scored.connect(_on_clear_scored)
	logic.lines_cleared.connect(_on_lines_cleared)
	logic.level_changed.connect(_on_level_changed)
	_refresh()

func _on_score_changed(new_score: int) -> void:
	score_label.text = "SCORE\n%d" % new_score

func _on_lines_cleared(_n: int) -> void:
	lines_label.text = "LINES\n%d" % logic.total_lines

func _on_level_changed(new_level: int) -> void:
	level_label.text = "LEVEL\n%d" % new_level

func _on_clear_scored(clear_type: String, points: int) -> void:
	combo_label.text = "%s\n+%d" % [clear_type, points]
	combo_label.modulate.a = 1.0
	combo_label.visible = true
	var tween = create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(combo_label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(func(): combo_label.visible = false)

func _refresh() -> void:
	score_label.text = "SCORE\n%d" % logic.scorer.score
	lines_label.text = "LINES\n%d" % logic.total_lines
	level_label.text = "LEVEL\n%d" % logic.current_level
