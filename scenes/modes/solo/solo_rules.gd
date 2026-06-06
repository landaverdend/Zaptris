extends Node

@onready var logic: Node = $"../GameArena/GameLogic"

func _ready() -> void:
	logic.lines_cleared.connect(_on_lines_cleared)

func _on_lines_cleared(_n: int) -> void:
	var new_level: int = (logic.total_lines / 10) + 1
	if new_level != logic.current_level:
		logic.set_gravity_level(new_level)
