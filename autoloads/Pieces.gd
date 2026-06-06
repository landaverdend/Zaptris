extends Node

# Direct port of pieces.ts
# Shapes: [piece][rotation] = array of [dr, dc] offsets relative to anchor

const PIECE_TYPES = ["I", "O", "T", "S", "Z", "J", "L"]

const COLORS = {
	"I": Color(0.0, 1.0, 1.0),
	"O": Color(1.0, 1.0, 0.0),
	"T": Color(0.6, 0.0, 0.8),
	"S": Color(0.0, 0.8, 0.0),
	"Z": Color(0.9, 0.1, 0.1),
	"J": Color(0.1, 0.1, 0.9),
	"L": Color(1.0, 0.5, 0.0),
}

const SHAPES = {
	"I": [
		[[1,0],[1,1],[1,2],[1,3]],
		[[0,2],[1,2],[2,2],[3,2]],
		[[2,0],[2,1],[2,2],[2,3]],
		[[0,1],[1,1],[2,1],[3,1]],
	],
	"O": [
		[[0,0],[0,1],[1,0],[1,1]],
		[[0,0],[0,1],[1,0],[1,1]],
		[[0,0],[0,1],[1,0],[1,1]],
		[[0,0],[0,1],[1,0],[1,1]],
	],
	"T": [
		[[0,1],[1,0],[1,1],[1,2]],
		[[0,1],[1,1],[1,2],[2,1]],
		[[1,0],[1,1],[1,2],[2,1]],
		[[0,1],[1,0],[1,1],[2,1]],
	],
	"S": [
		[[0,1],[0,2],[1,0],[1,1]],
		[[0,0],[1,0],[1,1],[2,1]],
		[[0,1],[0,2],[1,0],[1,1]],
		[[0,0],[1,0],[1,1],[2,1]],
	],
	"Z": [
		[[0,0],[0,1],[1,1],[1,2]],
		[[0,1],[1,0],[1,1],[2,0]],
		[[0,0],[0,1],[1,1],[1,2]],
		[[0,1],[1,0],[1,1],[2,0]],
	],
	"J": [
		[[0,0],[1,0],[1,1],[1,2]],
		[[0,1],[0,2],[1,1],[2,1]],
		[[1,0],[1,1],[1,2],[2,2]],
		[[0,1],[1,1],[2,0],[2,1]],
	],
	"L": [
		[[0,2],[1,0],[1,1],[1,2]],
		[[0,1],[1,1],[2,1],[2,2]],
		[[1,0],[1,1],[1,2],[2,0]],
		[[0,0],[0,1],[1,1],[2,1]],
	],
}

# ── SRS wall-kick tables ──────────────────────────────────────────────────────
# Offsets are [dc, dr] — column first, row second — matching the TS source.
# Indexed by from_rotation (0=spawn, 1=R, 2=2, 3=L).

const JLSTZ_CW = [
	[[0,0],[-1,0],[-1,-1],[0, 2],[-1, 2]],  # 0→R
	[[0,0],[ 1,0],[ 1, 1],[0,-2],[ 1,-2]],  # R→2
	[[0,0],[ 1,0],[ 1,-1],[0, 2],[ 1, 2]],  # 2→L
	[[0,0],[-1,0],[-1, 1],[0,-2],[-1,-2]],  # L→0
]
const JLSTZ_CCW = [
	[[0,0],[ 1,0],[ 1,-1],[0, 2],[ 1, 2]],  # 0→L
	[[0,0],[ 1,0],[ 1, 1],[0,-2],[ 1,-2]],  # R→0
	[[0,0],[-1,0],[-1,-1],[0, 2],[-1, 2]],  # 2→R
	[[0,0],[-1,0],[-1, 1],[0,-2],[-1,-2]],  # L→2
]
const I_CW = [
	[[0,0],[-2,0],[ 1,0],[-2, 1],[ 1,-2]],  # 0→R
	[[0,0],[-1,0],[ 2,0],[-1,-2],[ 2, 1]],  # R→2
	[[0,0],[ 2,0],[-1,0],[ 2,-1],[-1, 2]],  # 2→L
	[[0,0],[ 1,0],[-2,0],[ 1, 2],[-2,-1]],  # L→0
]
const I_CCW = [
	[[0,0],[-1,0],[ 2,0],[-1,-2],[ 2, 1]],  # 0→L
	[[0,0],[ 2,0],[-1,0],[ 2,-1],[-1, 2]],  # R→0
	[[0,0],[ 1,0],[-2,0],[ 1, 2],[-2,-1]],  # 2→R
	[[0,0],[-2,0],[ 1,0],[-2, 1],[ 1,-2]],  # L→2
]

# Returns the 5 SRS kick candidates for a rotation attempt.
# Each entry is [dc, dr] — apply to current col/row to get the candidate position.
static func kick_offsets(kind: String, from_rotation: int, cw: bool) -> Array:
	var i = from_rotation % 4
	if kind == "O":
		return [[0,0]]  # O piece never needs kicks
	if kind == "I":
		return I_CW[i] if cw else I_CCW[i]
	return JLSTZ_CW[i] if cw else JLSTZ_CCW[i]

# Returns [dr, dc] offsets for a piece at a given rotation
static func cells(kind: String, rotation: int) -> Array:
	return SHAPES[kind][rotation % 4]

# Returns world [row, col] positions for an active piece
static func board_cells(piece: ActivePiece) -> Array:
	var result = []
	for offset in cells(piece.kind, piece.rotation):
		result.append([piece.row + offset[0], piece.col + offset[1]])
	return result

# Spawn column — O piece spawns one col to the right
static func spawn_col(kind: String) -> int:
	return 4 if kind == "O" else 3
