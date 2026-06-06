extends Node3D

const BLOCK_SCENE := preload("res://scenes/game/block.tscn")

@onready var logic: Node = $"../GameLogic"
@onready var piece_display: Node3D = $PieceDisplay

func _ready() -> void:
	logic.hold_changed.connect(_render_hold)

func _render_hold() -> void:
	# Clear previous display blocks
	for child in piece_display.get_children():
		child.queue_free()

	if logic.hold_piece == "":
		return

	var kind: String = logic.hold_piece
	var color: Color = Pieces.COLORS[kind]
	var cells: Array = Pieces.cells(kind, 0)  # always show at spawn rotation

	# Find bounding box so we can center the piece inside the display area
	var min_col: int = cells[0][1]
	var max_col: int = cells[0][1]
	var min_row: int = cells[0][0]
	var max_row: int = cells[0][0]
	for cell in cells:
		min_col = mini(min_col, cell[1])
		max_col = maxi(max_col, cell[1])
		min_row = mini(min_row, cell[0])
		max_row = maxi(max_row, cell[0])

	var center_col: float = (min_col + max_col) / 2.0
	var center_row: float = (min_row + max_row) / 2.0

	for cell in cells:
		var block = BLOCK_SCENE.instantiate()
		piece_display.add_child(block)
		# Y is negated because grid rows increase downward, world Y increases upward
		block.position = Vector3(
			cell[1] - center_col,
			-(cell[0] - center_row),
			0.0
		)
		block.set_color(color)
