extends Node
class_name GameLogic

const COLS = 10
const ROWS = 23           # 3 buffer + 20 visible
const BUFFER_ROWS = 3     # hidden rows above the visible board (rows 0–2)
const DANGER_ROWS = 2     # rows 0–1 are the kill zone — piece here = X warning
var cell_size: int = 36

const LOCK_DELAY_FRAMES = 30    # frames before a floored piece locks (500ms @ 60Hz)
const MAX_LOCK_RESETS = 25      # max moves/rotations that can reset the lock timer
const GARBAGE_DELAY_FRAMES = 240  # 4s at 60fps — matches Stacktris (60 * 4)

var garbage_enabled: bool = false
var garbage_queue: Array = []   # Array of {lines: int, frames: int, gap_col: int}

var grid: Array = []
var active_piece: ActivePiece = null
var bag: PieceBag = null
var scorer: ScoreTracker = null
var score: int:
	get: return scorer.score if scorer else 0
var current_level: int = 1     # set externally via set_gravity_level()
var gravity_speed: float = 0.0  # set in _ready() via gravity_for_level()
var gravity_accumulator: float = 0.0
var hold_piece: String = ""   # empty = nothing held
var hold_used: bool = false
var total_lines: int = 0

signal grid_changed
signal piece_changed
signal queue_changed
signal hold_changed
signal lines_cleared(n: int)
signal level_changed(new_level: int)
signal game_over
signal pending_garbage_changed(total: int)
signal attack_generated(lines: int)
signal hard_drop_performed(kind: String, rotation: int, col: int, start_row: int, end_row: int)
signal lines_about_to_clear(rows: Array, clear_type: String, origin_col: float)

func _ready() -> void:
	_init_grid()
	bag = PieceBag.new(randi())
	scorer = ScoreTracker.new()
	gravity_speed = gravity_for_level(1)

# Called by the game mode (e.g. SoloMode) once the countdown finishes.
func start() -> void:
	spawn_piece()

# ── Main tick ─────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_tick_garbage()
	if active_piece == null:
		return
	if active_piece.is_floored:
		_tick_lock_delay()
	else:
		_tick_fall()

func _tick_fall() -> void:
	gravity_accumulator += gravity_speed
	var rows := int(floor(gravity_accumulator))
	gravity_accumulator -= rows

	for _i in range(rows):
		if _is_valid(active_piece.row + 1, active_piece.col, active_piece.rotation):
			active_piece.row += 1
			active_piece.just_spawned = false
			if active_piece.row > active_piece.highest_row:
				active_piece.highest_row = active_piece.row
				active_piece.total_resets = 0
		else:
			active_piece.is_floored = true
			break
	piece_changed.emit()

func _tick_lock_delay() -> void:
	active_piece.time_on_floor += 1
	piece_changed.emit()  # drives the dimming animation in board.gd every frame

	if active_piece.time_on_floor >= LOCK_DELAY_FRAMES:
		# Safety snap — handles edge case where a rotation kick left the piece airborne
		# on the same tick the timer expired
		while _is_valid(active_piece.row + 1, active_piece.col, active_piece.rotation):
			active_piece.row += 1
		lock_piece()
		return

	# If the piece can fall again (e.g. slid off a ledge) exit lock delay
	if _is_valid(active_piece.row + 1, active_piece.col, active_piece.rotation):
		active_piece.is_floored = false

# Called after any successful move or rotate while the piece is floored
func _handle_lock_reset() -> void:
	active_piece.total_resets += 1
	if active_piece.total_resets <= MAX_LOCK_RESETS:
		active_piece.time_on_floor = 0

func _init_grid() -> void:
	grid.clear()
	for _row in range(ROWS):
		var row: Array = []
		for _col in range(COLS):
			row.append(null)
		grid.append(row)

func spawn_piece(kind: String = "") -> void:
	if kind == "":
		kind = bag.next()
	var p = ActivePiece.new()
	p.kind = kind
	p.col = Pieces.spawn_col(kind)
	# Spawn at row 1 (kill zone, grace period suppresses X), fall back to row 0
	var spawned := false
	for try_row in range(DANGER_ROWS - 1, -1, -1):
		p.row = try_row
		if _is_valid(p.row, p.col, 0, kind):
			spawned = true
			break
	if not spawned:
		active_piece = null
		print("game over: block-out at spawn")
		game_over.emit()
		return
	active_piece = p
	gravity_accumulator = 0.0
	piece_changed.emit()
	queue_changed.emit()

# Called by the game mode to restart without re-entering the scene tree.
# Preserves all signal connections — ScoreTracker is reset in-place, not replaced.
# Caller supplies the seed — pass randi() for solo, a server-broadcast value for multiplayer.
func reset(bag_seed: int) -> void:
	_init_grid()
	scorer.reset()
	bag = PieceBag.new(bag_seed)
	active_piece = null
	hold_piece = ""
	hold_used = false
	total_lines = 0
	gravity_accumulator = 0.0
	set_gravity_level(1)   # resets current_level, gravity_speed, emits level_changed
	garbage_queue.clear()
	grid_changed.emit()
	hold_changed.emit()
	queue_changed.emit()
	pending_garbage_changed.emit(0)

# ── Gravity interface ─────────────────────────────────────────────────────────

# Direct port of gravityForLevel() from stacktris state.ts
static func gravity_for_level(level: int) -> float:
	var capped: int = mini(level, 40)
	if capped <= 15:
		return 0.02 * capped
	return 0.30 * pow(1.65, capped - 15)

func set_gravity_level(level: int) -> void:
	current_level = level
	gravity_speed = gravity_for_level(level)
	level_changed.emit(level)

# ── Collision ─────────────────────────────────────────────────────────────────

func _is_valid(row: int, col: int, rotation: int, kind: String = "") -> bool:
	var k = kind if kind != "" else active_piece.kind
	for offset in Pieces.cells(k, rotation):
		var r = row + offset[0]
		var c = col + offset[1]
		if r < 0 or r >= ROWS or c < 0 or c >= COLS:
			return false
		if grid[r][c] != null:
			return false
	return true

# ── Attack ────────────────────────────────────────────────────────────────────
# Garbage lines sent per clear type — direct port of Stacktris GARBAGE_TABLE
# and T_SPIN_GARBAGE (gameEngine.ts). B2B adds +1 on top.
const ATTACK_TABLE := {
	"single":            0,
	"double":            1,
	"triple":            2,
	"tetris":            4,
	"tspin_single":      2,
	"tspin_double":      4,
	"tspin_triple":      6,
	"mini_tspin":        0,
	"mini_tspin_single": 1,
	"tspin":             0,  # t-spin with no lines cleared — no attack
}

# Clears that qualify for the B2B +1 bonus when chained consecutively.
const B2B_ATTACK_QUALIFYING := [
	"tetris", "tspin_single", "tspin_double", "tspin_triple", "mini_tspin_single"
]

func _compute_attack(clear_type: String, was_b2b: bool) -> int:
	var base: int = ATTACK_TABLE.get(clear_type, 0)
	var b2b_bonus := 1 if (was_b2b and clear_type in B2B_ATTACK_QUALIFYING) else 0
	return base + b2b_bonus

# ── Garbage ───────────────────────────────────────────────────────────────────

# Called by the room (LocalRules) to queue incoming garbage lines.
# Each batch gets a random gap column and ticks down over GARBAGE_DELAY_FRAMES.
func receive_garbage(lines: int) -> void:
	if not garbage_enabled or lines <= 0:
		return
	garbage_queue.append({
		"lines":   lines,
		"frames":  GARBAGE_DELAY_FRAMES,
		"gap_col": randi_range(0, COLS - 1)
	})
	pending_garbage_changed.emit(get_pending_garbage())

func get_pending_garbage() -> int:
	var total := 0
	for batch in garbage_queue:
		total += batch["lines"]
	return total

func _tick_garbage() -> void:
	if not garbage_enabled or garbage_queue.is_empty():
		return
	var batch: Dictionary = garbage_queue[0]
	batch["frames"] -= 1
	if batch["frames"] > 0:
		return
	garbage_queue.pop_front()
	_push_garbage(batch["lines"], batch["gap_col"])

func _push_garbage(lines: int, gap_col: int) -> void:
	for _i in range(lines):
		grid.pop_front()  # top row scrolls off
		var new_row: Array = []
		for c in range(COLS):
			if c == gap_col:
				new_row.append(null)
			else:
				new_row.append(Color(0.45, 0.45, 0.45))
		grid.append(new_row)
	# Shift active piece up to match the rising board.
	if active_piece != null:
		active_piece.row -= lines
		# Clamp so no cell goes above row 0 — garbage can push a piece into the
		# buffer zone but can't eject it from the grid entirely.
		# min_dr is the smallest row offset in the piece's current shape;
		# the piece can sit as high as row = -min_dr before any cell leaves the grid.
		var min_dr := 0
		for offset in Pieces.cells(active_piece.kind, active_piece.rotation):
			min_dr = min(min_dr, offset[0])
		active_piece.row = max(active_piece.row, -min_dr)
		# Game over only if the clamped position overlaps locked cells.
		if not _is_valid(active_piece.row, active_piece.col, active_piece.rotation):
			active_piece = null
			game_over.emit()
			return
	pending_garbage_changed.emit(get_pending_garbage())
	grid_changed.emit()

# ── Ghost piece ───────────────────────────────────────────────────────────────

func get_ghost_row() -> int:
	if active_piece == null:
		return -1
	var ghost_row = active_piece.row
	while _is_valid(ghost_row + 1, active_piece.col, active_piece.rotation):
		ghost_row += 1
	return ghost_row

# ── Movement ──────────────────────────────────────────────────────────────────

func try_move(dr: int, dc: int) -> bool:
	if _is_valid(active_piece.row + dr, active_piece.col + dc, active_piece.rotation):
		active_piece.row += dr
		active_piece.col += dc
		if active_piece.is_floored:
			_handle_lock_reset()
		active_piece.last_action_was_rotation = false
		piece_changed.emit()
		return true
	return false

func try_rotate(dir: int) -> bool:
	var new_rot = (active_piece.rotation + dir + 4) % 4
	var kicks = Pieces.kick_offsets(active_piece.kind, active_piece.rotation, dir == 1)
	for kick in kicks:
		var dc = kick[0]
		var dr = kick[1]
		if _is_valid(active_piece.row + dr, active_piece.col + dc, new_rot):
			active_piece.row += dr
			active_piece.col += dc
			active_piece.rotation = new_rot
			active_piece.last_action_was_rotation = true
			if active_piece.is_floored:
				_handle_lock_reset()
			piece_changed.emit()
			return true
	return false

# Soft drop — player-initiated, awards 1 point per row
func soft_drop() -> void:
	if _is_valid(active_piece.row + 1, active_piece.col, active_piece.rotation):
		active_piece.row += 1
		active_piece.just_spawned = false
		if active_piece.row > active_piece.highest_row:
			active_piece.highest_row = active_piece.row
			active_piece.total_resets = 0
		scorer.on_soft_drop(1)
		gravity_accumulator = 0.0
		piece_changed.emit()

func hard_drop() -> void:
	var start_row := active_piece.row
	while _is_valid(active_piece.row + 1, active_piece.col, active_piece.rotation):
		active_piece.row += 1
	scorer.on_hard_drop(active_piece.row - start_row)
	hard_drop_performed.emit(active_piece.kind, active_piece.rotation, active_piece.col, start_row, active_piece.row)
	lock_piece()

# ── Locking & line clears ─────────────────────────────────────────────────────

func hold() -> void:
	if hold_used or active_piece == null:
		return
	var current_kind = active_piece.kind
	if hold_piece == "":
		hold_piece = current_kind
		spawn_piece()
	else:
		var swapped = hold_piece
		hold_piece = current_kind
		spawn_piece(swapped)
	hold_used = true
	hold_changed.emit()

func lock_piece() -> void:
	# Check T-spin before writing to grid — corners are checked against other
	# locked cells, not the piece itself, so order doesn't matter, but this
	# is cleaner conceptually (evaluating the move that just happened)
	var tspin := Rules.is_tspin(grid, active_piece)

	var color = Pieces.COLORS[active_piece.kind]
	var origin_col := _piece_origin_col()

	var locked_in_danger := false
	for cell in Pieces.board_cells(active_piece):
		var r = cell[0]
		var c = cell[1]
		if r >= 0 and r < ROWS and c >= 0 and c < COLS:
			grid[r][c] = color
		if r < DANGER_ROWS:
			locked_in_danger = true
	active_piece = null
	hold_used = false
	if locked_in_danger:
		grid_changed.emit()
		print("game over: lock-out in danger zone")
		game_over.emit()
		return
	var full_rows := _find_full_rows()
	if full_rows.size() > 0:
		var clear_type_preview := Rules.classify(full_rows.size(), tspin)
		lines_about_to_clear.emit(full_rows, clear_type_preview, origin_col)
	var cleared := _clear_lines()
	var clear_type := Rules.classify(cleared, tspin)
	if clear_type != "":
		print("clear: ", clear_type)
		# Capture B2B state BEFORE scorer updates it — same order as Stacktris
		var was_b2b: bool = scorer.b2b
		scorer.on_clear(clear_type, current_level)
		total_lines += cleared
		lines_cleared.emit(cleared)
		var attack := _compute_attack(clear_type, was_b2b)
		if attack > 0:
			attack_generated.emit(attack)
	grid_changed.emit()
	spawn_piece()

# Returns the horizontal midpoint (in grid-column units) of the active piece.
# Averages the dc offsets of all cells so the result is accurate for every
# piece shape and rotation. Must be called before active_piece is nulled.
func _piece_origin_col() -> float:
	var offsets := Pieces.cells(active_piece.kind, active_piece.rotation)
	var sum_dc := 0
	for offset in offsets:
		sum_dc += offset[1]
	return active_piece.col + float(sum_dc) / float(offsets.size())

func _find_full_rows() -> Array:
	var rows: Array = []
	for r in range(ROWS):
		var full := true
		for cell in grid[r]:
			if cell == null:
				full = false
				break
		if full:
			rows.append(r)
	return rows

func _clear_lines() -> int:
	var new_grid: Array = []
	var cleared := 0
	for row in grid:
		var full := true
		for cell in row:
			if cell == null:
				full = false
				break
		if not full:
			new_grid.append(row)
		else:
			cleared += 1
	for _i in range(cleared):
		var empty_row: Array = []
		for _col in range(COLS):
			empty_row.append(null)
		new_grid.insert(0, empty_row)
	grid = new_grid
	return cleared
