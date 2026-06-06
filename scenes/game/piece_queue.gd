extends Node2D

const QUEUE_COUNT = 5

@onready var logic: Node = $"../GameLogic"

func _ready() -> void:
	logic.queue_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var preview_cell: int = int(logic.cell_size) * 2 / 3
	var slot_height: int  = preview_cell * 4 + 12
	var queue: Array = logic.bag.peek(QUEUE_COUNT)
	for i in range(queue.size()):
		var kind: String = queue[i]
		var color: Color = Pieces.COLORS[kind]
		var slot_y: float = i * slot_height
		for offset in Pieces.cells(kind, 0):
			var dr: int = offset[0]
			var dc: int = offset[1]
			draw_rect(
				Rect2(dc * preview_cell + 2, slot_y + dr * preview_cell + 2, preview_cell - 2, preview_cell - 2),
				color
			)
