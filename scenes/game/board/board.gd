extends Node3D

const WARNING_THRESHOLD = 3  # locked cell within top N visible rows triggers warning

const BLOCK_SCENE := preload("res://scenes/game/board/block.tscn")

# Grid constants — mirror GameLogic so board.gd doesn't depend on its internals.
const TOTAL_ROWS  := 23  # GameLogic.ROWS
const BUFFER_ROWS := 3   # rows 0-2 are hidden above the visible board
const BOTTOM_ROW  := 22  # TOTAL_ROWS - 1; maps to world Y = 0.5
const COLS        := 10  # GameLogic.COLS

# ── Line-clear animation timing ────────────────────────────────────────────────
const CLEAR_STAGGER      : float = 0.03  # seconds between each column (left → right)
const CLEAR_FLASH_DUR    : float = 0.1  # scale-up (pop) duration per block
const CLEAR_COLLAPSE_DUR : float = 0.10  # scale-down (vanish) duration per block

# ── Hard-drop streak timing ────────────────────────────────────────────────────
const HARD_DROP_OPACITY  : float = 0.0075
const HARD_DROP_FADE_DUR : float = 0.45  # seconds for the teardrop to dissipate

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

# Set while a line-clear animation is playing — suppresses the grid_changed
# visual rebuild until the animation hands off control manually.
var _clearing: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_create_piece_nodes()
	logic.grid_changed.connect(_render_locked_cells)
	logic.piece_changed.connect(_render_active_piece)
	logic.hard_drop_performed.connect(_on_hard_drop)
	logic.lines_about_to_clear.connect(_on_lines_about_to_clear)

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
	if _clearing:
		return
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

		# Ghost block: hide when overlapping the active piece, or during line-clear.
		_ghost_blocks[i].position = grid_to_world(gr, c)
		_ghost_blocks[i].visible  = gr >= BUFFER_ROWS and ghost_row != piece.row and not _clearing

# ── Line clear animation ──────────────────────────────────────────────────────

func _on_lines_about_to_clear(rows: Array, _clear_type: String, origin_col: float) -> void:
	_clearing = true

	# Build a fast lookup for which rows are being cleared.
	var clearing_set: Dictionary = {}
	for row in rows:
		clearing_set[row] = true

	# Pull the block nodes for cleared rows out of _locked_nodes so the
	# deferred rebuild doesn't free them before the animation finishes.
	var to_animate: Array = []
	for row in rows:
		for col in range(COLS):
			var key := Vector2i(col, row)
			if _locked_nodes.has(key):
				to_animate.append({ "node": _locked_nodes[key], "col": col })
				_locked_nodes.erase(key)

	if to_animate.is_empty():
		_clearing = false
		return

	# The piece was written to grid[] before this signal fired, but grid_changed
	# is suppressed by _clearing. Render any cells that are in the grid but not
	# yet in _locked_nodes (the newly locked piece's non-cleared cells) so they
	# appear immediately instead of popping in after the animation ends.
	for row in range(TOTAL_ROWS):
		if clearing_set.has(row):
			continue  # these cells are being animated, skip them
		for col in range(COLS):
			var key := Vector2i(col, row)
			if _locked_nodes.has(key):
				continue  # already has a node
			var color = logic.grid[row][col]
			if color != null:
				var block = BLOCK_SCENE.instantiate()
				add_child(block)
				block.position = grid_to_world(row, col)
				block.set_color(color)
				_locked_nodes[key] = block

	# Farthest possible distance from origin to either edge of the board.
	var max_dist := maxf(absf(0.5 - origin_col), absf(float(COLS) - 0.5 - origin_col))

	for entry in to_animate:
		var block  = entry["node"]
		var col: int = entry["col"]

		# Stagger outward from the piece's center column.
		# Blocks equidistant on each side fire together for a symmetric burst.
		var dist  := absf(float(col) + 0.5 - origin_col)
		var delay := dist * CLEAR_STAGGER

		var tween := create_tween()
		tween.tween_interval(delay)
		# Flash up.
		tween.tween_property(block, "scale", Vector3(1.3, 1.3, 1.3), CLEAR_FLASH_DUR) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Collapse to nothing.
		tween.tween_property(block, "scale", Vector3.ZERO, CLEAR_COLLAPSE_DUR) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(block.queue_free)

	# Single cleanup tween fires after the farthest block finishes.
	var total_dur := max_dist * CLEAR_STAGGER + CLEAR_FLASH_DUR + CLEAR_COLLAPSE_DUR + 0.05
	var cleanup   := create_tween()
	cleanup.tween_callback(func() -> void:
		_clearing = false
		_render_locked_cells()
	).set_delay(total_dur)

# ── Hard drop effect ──────────────────────────────────────────────────────────

func _on_hard_drop(kind: String, rotation: int, col: int, start_row: int, end_row: int) -> void:
	if end_row == start_row:
		return  # piece was already on the floor, nothing to show

	var offsets = Pieces.cells(kind, rotation)
	var min_dc: int = offsets[0][1]
	var max_dc: int = offsets[0][1]
	var min_dr: int = offsets[0][0]
	var max_dr: int = offsets[0][0]
	for offset in offsets:
		if offset[1] < min_dc: min_dc = offset[1]
		if offset[1] > max_dc: max_dc = offset[1]
		if offset[0] < min_dr: min_dr = offset[0]
		if offset[0] > max_dr: max_dr = offset[0]

	var left_x   := float(col + min_dc)
	var right_x  := float(col + max_dc + 1)
	var top_y    := float(BOTTOM_ROW - (start_row + min_dr)) + 1.0
	var bottom_y := float(BOTTOM_ROW - (end_row   + max_dr)) + 1.0

	var height := top_y - bottom_y

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/game/effects/hard_drop_streak.gdshader")
	mat.set_shader_parameter("intensity", HARD_DROP_OPACITY)

	var quad := QuadMesh.new()
	quad.size = Vector2(right_x - left_x, height)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = Vector3(
		(left_x + right_x) * 0.5,
		(top_y  + bottom_y) * 0.5,
		0.1
	)
	add_child(mi)

	# Flash in, then dissipate in place.
	var tween := create_tween()
	tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("intensity", v),
		HARD_DROP_OPACITY, 0.0, HARD_DROP_FADE_DUR
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(mi.queue_free)

	_spawn_drop_particles(
		(left_x + right_x) * 0.5,
		(top_y  + bottom_y) * 0.5,
		right_x - left_x,
		height
	)

func _spawn_drop_particles(cx: float, cy: float, width: float, height: float) -> void:
	# Color ramp: bright white → transparent over particle lifetime.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad

	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(width * 0.5, height * 0.5, 0.0)
	proc_mat.direction            = Vector3(0.0, 1.0, 0.0)
	proc_mat.spread               = 25.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 8.0
	proc_mat.scale_min            = 0.2
	proc_mat.scale_max            = 0.5
	proc_mat.gravity              = Vector3(0.0, -4.0, 0.0)
	proc_mat.color_ramp           = grad_tex

	# Bright quad — high emission energy feeds the glow bloom.
	var part_mat := StandardMaterial3D.new()
	part_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mat.vertex_color_use_as_albedo = true
	part_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	part_mat.emission_enabled           = true
	part_mat.emission                   = Color.WHITE
	part_mat.emission_energy_multiplier = 10.0

	var part_mesh := QuadMesh.new()
	part_mesh.size     = Vector2(0.3, 0.3)
	part_mesh.material = part_mat

	var particles := GPUParticles3D.new()
	particles.amount        = 15
	particles.lifetime      = 0.7
	particles.one_shot      = true
	particles.explosiveness = 0.9
	particles.randomness    = 0.4
	particles.process_material = proc_mat
	particles.draw_pass_1      = part_mesh
	particles.position         = Vector3(cx, cy, 0.15)
	add_child(particles)

	# Free once the burst is done.
	var tween := create_tween()
	tween.tween_callback(particles.queue_free).set_delay(particles.lifetime + 0.3)
