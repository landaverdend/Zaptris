extends Node

# ── Clear classification ───────────────────────────────────────────────────────
#
# Called after a piece locks. Returns a string label for the type of clear,
# or "" if no lines were cleared.
#
# Two inputs drive the classification:
#   1. lines  — how many rows were cleared (1–4)
#   2. tspin  — whether the lock qualifies as a T-spin (see is_tspin below)
#
# T-spin clears outrank their plain equivalents in every scoring system,
# so we check T-spin first and branch from there.

static func classify(lines: int, tspin: bool) -> String:
	if lines == 0:
		# Piece locked but no lines cleared — happens constantly, not a scored event
		return ""

	if tspin:
		match lines:
			1: return "tspin_single"
				# Rotated into a tight spot and cleared one line.
				# Worth more than a plain single — rewards precise rotation play.
			2: return "tspin_double"
				# The classic T-spin double (TSD): rotated T into a 2-high cavity.
				# One of the most valuable scoring moves in competitive Tetris.
			3: return "tspin_triple"
				# T-spin triple (TST): very rare, requires a specific tower setup.
				# Highest single-move attack in standard Tetris.

	match lines:
		1: return "single"
			# One line cleared. Low value, but clears space.
		2: return "double"
			# Two lines at once. Modest efficiency.
		3: return "triple"
			# Three lines at once. Good efficiency.
		4: return "tetris"
			# Four lines with an I piece — the highest plain clear.
			# Efficient and triggers B2B when chained.

	return ""  # should never reach here

# ── T-spin detection (3-corner rule) ──────────────────────────────────────────
#
# Port of isTSpin() from stacktris board.ts.
#
# A lock counts as a T-spin when ALL THREE conditions hold:
#   1. The piece is a T.
#   2. The last action before locking was a rotation (not a move or gravity drop).
#      This prevents accidentally triggering a T-spin by sliding into a slot.
#   3. At least 3 of the 4 diagonal corners of the T's 3×3 bounding box are
#      occupied (by a locked cell or a wall). This is the "3-corner rule" used
#      by the official Tetris guideline.
#
# The T piece always sits in a 3×3 box. Its center cell is at (row+1, col+1).
# The four corners of that box — none of which the T piece itself occupies —
# are what we check. Walls count as occupied.

static func is_tspin(grid: Array, piece: ActivePiece) -> bool:
	# Condition 1 — only T pieces can T-spin
	if piece.kind != "T":
		return false

	# Condition 2 — last action must have been a rotation
	# A T piece slid or gravity-dropped into place does NOT count.
	if not piece.last_action_was_rotation:
		return false

	# Condition 3 — 3-corner rule
	# Center of the T's bounding box:
	var cr = piece.row + 1
	var cc = piece.col + 1

	var corners = [
		[cr - 1, cc - 1],  # top-left
		[cr - 1, cc + 1],  # top-right
		[cr + 1, cc - 1],  # bottom-left
		[cr + 1, cc + 1],  # bottom-right
	]

	var occupied := 0
	for corner in corners:
		if _is_occupied(grid, corner[0], corner[1]):
			occupied += 1

	return occupied >= 3

# A cell is "occupied" if it's out of bounds (wall) or contains a locked piece.
static func _is_occupied(grid: Array, r: int, c: int) -> bool:
	if r < 0 or r >= grid.size():
		return true  # above/below board = wall
	if c < 0 or c >= grid[0].size():
		return true  # left/right wall
	return grid[r][c] != null
