extends Node3D

@onready var value: Label3D = $Value

func setup(logic: Node, show: bool = true) -> void:
	visible = show
	logic.level_changed.connect(func(l: int): value.text = str(l))
	value.text = str(logic.current_level)
