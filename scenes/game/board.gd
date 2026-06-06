extends Node2D

const WARNING_THRESHOLD = 3  # locked cell within top N visible rows triggers warning

@onready var logic: Node = $"../GameLogic"

var _warn_piece_idx: int = 0

func _ready() -> void:
	logic.grid_changed.connect(queue_redraw)
	logic.piece_changed.connect(queue_redraw)
	logic.queue_changed.connect(_on_piece_spawned)
	logic.pending_garbage_changed.connect(queue_redraw)

func _draw_garbage_meter() -> void:
	if not logic.garbage_enabled:
		return
	var cell: int       = logic.cell_size
	var visible_rows: int = logic.ROWS - logic.BUFFER_ROWS
	var board_h: float  = visible_rows * cell
	var meter_x: float  = logic.COLS * cell + 4.0
	var meter_w: float  = 8.0

	# Dark background track — always visible when garbage is enabled
	draw_rect(Rect2(meter_x, 0.0, meter_w, board_h), Color(0.15, 0.15, 0.15))

	var total: int = logic.get_pending_garbage()
	if total == 0:
		return

	var capped: int    = mini(total, visible_rows)
	var line_h: float  = board_h / visible_rows
	var fill_h: float  = capped * line_h
	# Yellow up to 4 lines, red at 5+ — matches competitive Tetris conventions
	var fill_color: Color = Color.RED if total >= 5 else Color(1.0, 0.75, 0.0)
	draw_rect(Rect2(meter_x, board_h - fill_h, meter_w, fill_h), fill_color)

func _on_piece_spawned() -> void:
	if _is_warning():
		_warn_piece_idx = (_warn_piece_idx + 1) % Pieces.PIECE_TYPES.size()

func _process(_delta: float) -> void:
	# Keep redrawing every frame in warning mode so the pulse animates
	if _is_warning():
		queue_redraw()

func _is_warning() -> bool:
	var threshold = logic.BUFFER_ROWS + WARNING_THRESHOLD
	for row in range(logic.BUFFER_ROWS, threshold):
		for col in range(logic.COLS):
			if logic.grid[row][col] != null:
				return true
	return false

func _draw() -> void:
	var cols = logic.COLS
	var rows = logic.ROWS
	var buf  = logic.BUFFER_ROWS
	var cell: int = logic.cell_size
	var gap  = 2

	# Warning mode — cycle through piece shapes in the danger zone (rows 0–1)
	if _is_warning():
		var kind = Pieces.PIECE_TYPES[_warn_piece_idx]
		var pulse = sin(Time.get_ticks_msec() * 0.008) * 0.3 + 0.7
		var warn_color = Color(1.0, 0.0, 0.0, pulse)
		var anchor_col = (logic.COLS - 4) / 2  # center a 4-wide piece
		for offset in Pieces.cells(kind, 0):
			var r = offset[0]
			var c = anchor_col + offset[1]
			if r >= logic.DANGER_ROWS or c < 0 or c >= cols:
				continue
			var x  = c * cell + gap
			var y  = (r - buf) * cell + gap
			var cw = cell - gap
			var ch = cell - gap
			draw_rect(Rect2(x, y, cw, ch), warn_color)
			draw_line(Vector2(x, y),      Vector2(x + cw, y + ch), Color.RED, 2.0)
			draw_line(Vector2(x + cw, y), Vector2(x, y + ch),      Color.RED, 2.0)

	# Draw locked cells in buffer zone (no dark background)
	for row in range(buf):
		for col in range(cols):
			if logic.grid[row][col] != null:
				draw_rect(Rect2(col * cell + gap, (row - buf) * cell + gap, cell - gap, cell - gap), logic.grid[row][col])

	# Draw visible grid
	for row in range(buf, rows):
		for col in range(cols):
			var color = logic.grid[row][col] if logic.grid[row][col] != null else Color(0.15, 0.15, 0.15)
			draw_rect(Rect2(col * cell + gap, (row - buf) * cell + gap, cell - gap, cell - gap), color)

	if logic.active_piece == null:
		return

	var piece_color = Pieces.COLORS[logic.active_piece.kind]

	# Lock delay flash
	if logic.active_piece.is_floored:
		var progress = float(logic.active_piece.time_on_floor) / logic.LOCK_DELAY_FRAMES
		var frequency = lerp(3.0, 12.0, progress)
		var phase = float(logic.active_piece.time_on_floor) / 60.0 * frequency * TAU
		piece_color.a = lerp(0.3, 1.0, sin(phase) * 0.5 + 0.5)

	# Ghost — visible rows only
	var ghost_row = logic.get_ghost_row()
	if ghost_row > logic.active_piece.row:
		var ghost_color = Pieces.COLORS[logic.active_piece.kind]
		ghost_color.a = 0.25
		for offset in Pieces.cells(logic.active_piece.kind, logic.active_piece.rotation):
			var r = ghost_row + offset[0]
			var c = logic.active_piece.col + offset[1]
			if r >= buf and r < rows and c >= 0 and c < cols:
				draw_rect(Rect2(c * cell + gap, (r - buf) * cell + gap, cell - gap, cell - gap), ghost_color)

	# Active piece — X on cells in the danger zone
	for board_cell in Pieces.board_cells(logic.active_piece):
		var r = board_cell[0]
		var c = board_cell[1]
		if c < 0 or c >= cols or r >= rows:
			continue
		var x  = c * cell + gap
		var y  = (r - buf) * cell + gap
		var cw = cell - gap
		var ch = cell - gap
		draw_rect(Rect2(x, y, cw, ch), piece_color)
		if r < logic.DANGER_ROWS and not logic.active_piece.just_spawned:
			draw_line(Vector2(x, y),      Vector2(x + cw, y + ch), Color.RED, 2.0)
			draw_line(Vector2(x + cw, y), Vector2(x, y + ch),      Color.RED, 2.0)

	_draw_garbage_meter()
