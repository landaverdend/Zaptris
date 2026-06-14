extends Node3D

const BLOCK_SCENE   := preload("res://scenes/game/board/block.tscn")
const MAX_LINES     := 20
const GARBAGE_COLOR := Color(0.55, 0.04, 0.04)  # dark red

@onready var logic:  Node    = $"../GameLogic"
@onready var blocks: Node3D  = $Blocks

# Pre-created block nodes — toggled visible/invisible on each signal,
# never created or destroyed during play (same pattern as active/ghost blocks).
var _blocks: Array = []

func _ready() -> void:
	# Defer setup so game_arena._ready() has already propagated garbage_enabled
	# to logic before we check it. (_ready() fires bottom-up, so children run
	# before their parent — without deferral we'd always see garbage_enabled=false.)
	call_deferred("_initialize")

func _initialize() -> void:
	# Hide the whole meter in modes where garbage is disabled (e.g. solo).
	if not logic.garbage_enabled:
		visible = false
		return

	for i in range(MAX_LINES):
		var b = BLOCK_SCENE.instantiate()
		blocks.add_child(b)
		b.scale    = Vector3(0.55, 0.85, 0.4)
		b.position = Vector3(0.0, float(i) + 0.5, 0.0)
		b.set_color(GARBAGE_COLOR)
		b.visible  = false
		_blocks.append(b)

	logic.pending_garbage_changed.connect(_on_garbage_changed)

# Fired whenever the pending-garbage total changes.
# `total` is the sum of all queued batches.
func _on_garbage_changed(total: int) -> void:
	var count := clampi(total, 0, MAX_LINES)
	for i in range(_blocks.size()):
		_blocks[i].visible = i < count
