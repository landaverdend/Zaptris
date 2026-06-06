extends Node2D

@onready var logic: Node = $"../GameLogic"

func _ready() -> void:
	logic.hold_changed.connect(queue_redraw)

func _draw() -> void:
	if logic.hold_piece == "":
		return
	var preview_cell: int = int(logic.cell_size) * 2 / 3
	var color: Color = Pieces.COLORS[logic.hold_piece]
	if logic.hold_used:
		color.a = 0.35
	for offset in Pieces.cells(logic.hold_piece, 0):
		var dr: int = offset[0]
		var dc: int = offset[1]
		draw_rect(
			Rect2(dc * preview_cell + 2, dr * preview_cell + 2, preview_cell - 2, preview_cell - 2),
			color
		)
