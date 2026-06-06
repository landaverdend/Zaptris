extends Node

const WINS_TO_WIN := 3

# ── Signals ───────────────────────────────────────────────────────────────────

signal all_ready
signal round_over(winner_index: int)
signal match_over(winner_index: int)

# ── Ready tracking ────────────────────────────────────────────────────────────

var _ready_slots: Array = []

func setup(player_count: int) -> void:
	_ready_slots.clear()
	wins.clear()
	for i in range(player_count):
		_ready_slots.append(false)
		wins.append(0)

func set_ready(slot: int) -> void:
	if slot < 0 or slot >= _ready_slots.size():
		return
	if _ready_slots[slot]:
		return
	_ready_slots[slot] = true
	_check_all_ready()

func reset_ready() -> void:
	for i in range(_ready_slots.size()):
		_ready_slots[i] = false

func _check_all_ready() -> void:
	if _ready_slots.is_empty():
		return
	for r in _ready_slots:
		if not r:
			return
	all_ready.emit()

# ── Win tracking ──────────────────────────────────────────────────────────────

var wins: Array = []  # int per player slot, persists across rounds

func get_wins() -> Array:
	return wins

# ── Round tracking ────────────────────────────────────────────────────────────

var _arenas: Array = []
var _active_arenas: Array = []
# Per-attacker round-robin index — mirrors Stacktris's targetIndices.
# _target_indices[i] = next slot in _arenas that arena i will attack.
var _target_indices: Array = []

func start_round(arenas: Array) -> void:
	_cleanup_connections()
	_arenas = arenas
	_active_arenas.clear()
	_target_indices.clear()
	for i in range(arenas.size()):
		_active_arenas.append(i)
		# Each arena starts targeting the next one in order (circular)
		_target_indices.append((i + 1) % arenas.size())
		var logic: Node = arenas[i].get_node("GameLogic")
		logic.game_over.connect(_on_arena_game_over.bind(i))
		logic.attack_generated.connect(_on_attack_generated.bind(i))

func _on_arena_game_over(arena_index: int) -> void:
	_active_arenas.erase(arena_index)
	if _active_arenas.size() != 1:
		return
	var winner: int = _active_arenas[0]
	wins[winner] += 1
	if wins[winner] >= WINS_TO_WIN:
		match_over.emit(winner)
	else:
		round_over.emit(winner)

# ── Garbage routing ───────────────────────────────────────────────────────────

func _on_attack_generated(lines: int, attacker_index: int) -> void:
	var target := _get_next_target(attacker_index)
	if target < 0:
		return
	_arenas[target].get_node("GameLogic").receive_garbage(lines)

# Round-robin: find next alive arena that isn't the attacker, advance the index.
# Dead arenas remain in _arenas as tombstones but aren't in _active_arenas.
func _get_next_target(attacker_index: int) -> int:
	var n := _arenas.size()
	var idx: int = _target_indices[attacker_index]
	for _i in range(n):
		var candidate := idx
		idx = (idx + 1) % n
		if candidate != attacker_index and candidate in _active_arenas:
			_target_indices[attacker_index] = idx
			return candidate
	return -1

func _cleanup_connections() -> void:
	for arena in _arenas:
		if not is_instance_valid(arena):
			continue
		var logic: Node = arena.get_node("GameLogic")
		for conn in logic.game_over.get_connections():
			logic.game_over.disconnect(conn["callable"])
		for conn in logic.attack_generated.get_connections():
			logic.attack_generated.disconnect(conn["callable"])
