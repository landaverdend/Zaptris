class_name ScoreTracker extends RefCounted

# Owns score and B2B chain state only.
# Level is passed in from outside — the game session determines level, not scoring.

var score: int = 0
var b2b: bool = false  # true once a qualifying clear has started a B2B chain

signal score_changed(new_score: int)
signal clear_scored(clear_type: String, points: int)

# ── Scoring table (Official Tetris Guideline) ─────────────────────────────────

# Base points per clear type, multiplied by current level.
# T-Spin with no line clear still awards points.
const BASE_SCORES: Dictionary = {
	"single":           100,
	"double":           300,
	"triple":           500,
	"tetris":           800,   # 4-line clear with I piece — difficult clear
	"mini_tspin":       100,   # T-spin rotation into slot, no lines cleared
	"mini_tspin_single":200,   # T-spin mini clearing 1 line
	"tspin":            400,   # Full T-spin, no lines cleared
	"tspin_single":     800,   # T-spin clearing 1 line
	"tspin_double":     1200,  # T-spin clearing 2 lines
	"tspin_triple":     1600,  # T-spin clearing 3 lines (very rare)
}

# Qualifying clears that can START or CONTINUE a B2B chain.
# Singles, doubles, and triples BREAK the chain.
# T-spins and mini T-spins with no line clear do neither — they don't break
# the chain but also can't start one.
const B2B_QUALIFYING: Array = [
	"tetris",
	"tspin_single",
	"tspin_double",
	"tspin_triple",
	"mini_tspin_single",
]

# These clears break an active B2B chain.
const B2B_BREAKING: Array = [
	"single",
	"double",
	"triple",
]

# ── Public interface ──────────────────────────────────────────────────────────

func on_clear(clear_type: String, level: int) -> void:
	if clear_type == "":
		return

	var base: int = BASE_SCORES.get(clear_type, 0)
	if base == 0:
		return

	var total: int = base * level

	# B2B bonus — 0.5x the action total when chaining back-to-back difficult clears.
	# The FIRST clear in a B2B sequence does not receive the bonus;
	# only consecutive qualifying clears after it do.
	if B2B_QUALIFYING.has(clear_type) and b2b:
		total += int(base * level * 0.5)

	# Update B2B chain state AFTER calculating the bonus
	if B2B_QUALIFYING.has(clear_type):
		b2b = true   # start or continue the chain
	elif B2B_BREAKING.has(clear_type):
		b2b = false  # plain single/double/triple breaks it
	# tspin / mini_tspin (no lines) do nothing to B2B state

	score += total
	var b2b_bonus := B2B_QUALIFYING.has(clear_type) and b2b
	print("score +%d (%s%s) → total: %d" % [
		total, clear_type,
		" B2B" if b2b_bonus else "", score
	])
	score_changed.emit(score)
	clear_scored.emit(clear_type, total)

func reset() -> void:
	score = 0
	b2b = false
	score_changed.emit(score)

# Soft drop: 1 point per row manually dropped.
# Called once per row actually moved (not per keypress).
func on_soft_drop(rows: int) -> void:
	if rows <= 0:
		return
	score += rows
	score_changed.emit(score)

# Hard drop: 2 points per row fallen.
func on_hard_drop(rows: int) -> void:
	if rows <= 0:
		return
	score += rows * 2
	score_changed.emit(score)
