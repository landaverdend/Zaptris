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

	var center: Vector2 = Pieces.cells_center(cells)

	for cell in cells:
		var block = BLOCK_SCENE.instantiate()
		piece_display.add_child(block)
		# Y is negated because grid rows increase downward, world Y increases upward
		block.position = Vector3(
			cell[1] - center.x,
			-(cell[0] - center.y),
			0.0
		)
		block.set_color(color)
