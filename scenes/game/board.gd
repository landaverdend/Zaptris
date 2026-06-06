extends Node3D

const WARNING_THRESHOLD = 3  # locked cell within top N visible rows triggers warning

const BLOCK_SCENE := preload("res://scenes/game/block.tscn")

# Grid constants — mirror GameLogic so board.gd doesn't depend on its internals.
const TOTAL_ROWS  := 23  # GameLogic.ROWS
const BUFFER_ROWS := 3   # rows 0-2 are hidden above the visible board
const BOTTOM_ROW  := 22  # TOTAL_ROWS - 1; maps to world Y = 0.5
const COLS        := 10  # GameLogic.COLS

@onready var logic: Node = $"../GameLogic"

# 4 persistent block nodes for the active piece + 4 for its ghost.
# Repositioned every frame — never created/destroyed mid-game.
# Untyped so GDScript's static checker doesn't reject .set_color / .position
# calls on what it only knows is a Node.
var _active_blocks: Array = []
var _ghost_blocks:  Array = []

# Locked cell nodes keyed by grid position.
var _locked_nodes: Dictionary = {}  # Vector2i(col, row) → Node

# Cache the current piece kind so we only rebuild materials on a new spawn,
# not on every physics frame.
var _current_kind: String = ""

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_create_piece_nodes()
	logic.grid_changed.connect(_render_locked_cells)
	logic.piece_changed.connect(_render_active_piece)

func _create_piece_nodes() -> void:
	for i in range(4):
		var active := BLOCK_SCENE.instantiate()
		add_child(active)
		active.visible = false
		_active_blocks.append(active)

		var ghost := BLOCK_SCENE.instantiate()
		add_child(ghost)
		ghost.visible = false
		_ghost_blocks.append(ghost)

# ── Coordinate conversion ──────────────────────────────────────────────────────

# Converts a grid (row, col) index to a world-space Vector3 cell center.
# Row 22 (bottom) → Y = 0.5.  Row 3 (top visible) → Y = 19.5.
# Buffer rows 0-2 map above the backdrop (Y > 20) and are never rendered.
func grid_to_world(grid_row: int, grid_col: int) -> Vector3:
	return Vector3(
		grid_col + 0.5,
		float(BOTTOM_ROW - grid_row) + 0.5,
		0.0
	)

# ── Locked cells ───────────────────────────────────────────────────────────────

# Fired by grid_changed: piece locked, line cleared, or garbage received.
# Rebuilds all locked-cell visuals from scratch (cheap — fires rarely).
func _render_locked_cells() -> void:
	for node in _locked_nodes.values():
		node.queue_free()
	_locked_nodes.clear()

	for row in range(0, TOTAL_ROWS):
		for col in range(COLS):
			var color = logic.grid[row][col]
			if color != null:
				var block = BLOCK_SCENE.instantiate()
				add_child(block)
				block.position = grid_to_world(row, col)
				block.set_color(color)
				_locked_nodes[Vector2i(col, row)] = block

# ── Active piece + ghost ───────────────────────────────────────────────────────

# Fired by piece_changed every physics frame — only repositions nodes,
# rebuilds materials only when the piece kind changes (new spawn).
func _render_active_piece() -> void:
	if logic.active_piece == null:
		for b in _active_blocks: b.visible = false
		for g in _ghost_blocks:  g.visible = false
		_current_kind = ""
		return

	# Use plain = (not :=) — logic is typed as Node so GDScript can't infer
	# the return types of these dynamic property/method accesses.
	var piece = logic.active_piece
	var color: Color = Pieces.COLORS[piece.kind]
	var cells = Pieces.board_cells(piece)
	var ghost_row = logic.get_ghost_row()
	var row_offset = ghost_row - piece.row

	# Rebuild materials only on a new piece kind (spawn / hold swap).
	if piece.kind != _current_kind:
		_current_kind = piece.kind
		for b in _active_blocks: b.set_color(color)
		for g in _ghost_blocks:  g.set_color(color, true)

	for i in range(4):
		var r: int = cells[i][0]
		var c: int = cells[i][1]
		var gr: int = r + row_offset

		# Active block — always visible, including buffer/kill zone rows above the board.
		_active_blocks[i].position = grid_to_world(r, c)
		_active_blocks[i].visible  = true

		# Ghost block: hide when it perfectly overlaps the active piece
		# (piece is already resting on the stack).
		_ghost_blocks[i].position = grid_to_world(gr, c)
		_ghost_blocks[i].visible  = gr >= BUFFER_ROWS and ghost_row != piece.row
