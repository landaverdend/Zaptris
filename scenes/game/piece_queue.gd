extends Node3D

const BLOCK_SCENE    := preload("res://scenes/game/block.tscn")
const PREVIEW_COUNT  := 5
const PREVIEW_SCALE  := 0.5   # blocks render at half size inside the queue
const SLOT_SPACING   := 2.5   # world units between slot centers

@onready var logic: Node   = $"../GameLogic"
@onready var slots: Node3D = $Slots

func _ready() -> void:
	logic.queue_changed.connect(_render_queue)

func _render_queue() -> void:
	for child in slots.get_children():
		child.queue_free()

	var bag        = logic.bag
	var upcoming: Array = bag.peek(PREVIEW_COUNT)

	for i in range(upcoming.size()):
		var kind:  String = upcoming[i]
		var color: Color  = Pieces.COLORS[kind]
		var cells: Array  = Pieces.cells(kind, 0)  # always show at spawn rotation

		# Slot descends downward from the queue root
		var slot := Node3D.new()
		slot.position = Vector3(0.0, -i * SLOT_SPACING, 0.0)
		slots.add_child(slot)

		# Scale the display down so pieces don't dominate the layout
		var display := Node3D.new()
		display.scale = Vector3(PREVIEW_SCALE, PREVIEW_SCALE, PREVIEW_SCALE)
		slot.add_child(display)

		var center: Vector2 = Pieces.cells_center(cells)

		for cell in cells:
			var block = BLOCK_SCENE.instantiate()
			display.add_child(block)
			block.position = Vector3(
				cell[1] - center.x,
				-(cell[0] - center.y),
				0.0
			)
			block.set_color(color)
