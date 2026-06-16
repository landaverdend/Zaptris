extends Node3D

@onready var value: Label3D = $Value
var _total: int = 0

func setup(show: bool = false) -> void:
	visible = show
	_total = 0
	value.text = "0"

func add_sats(amount: int) -> void:
	_total += amount
	value.text = str(_total)
