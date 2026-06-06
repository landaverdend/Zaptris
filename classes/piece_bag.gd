class_name PieceBag extends RefCounted

# Maintains a lookahead queue of upcoming pieces using 7-bag randomization.
# A "bag" is a shuffled set of all 7 piece types — the queue is always kept
# topped up so peek() can look ahead without triggering a refill mid-peek.

const QUEUE_SIZE = 10  # how many pieces to keep buffered (peek up to 5 visible)

var _rng := RandomNumberGenerator.new()
var _current_bag: Array = []
var _queue: Array = []

func _init(seed: int) -> void:
	_rng.seed = seed
	while _queue.size() < QUEUE_SIZE:
		_queue.append(_draw_one())

# Consume the next piece from the queue and refill the tail.
func next() -> String:
	var piece: String = _queue.pop_front()
	_queue.append(_draw_one())
	return piece

# Look ahead at the next N pieces without consuming them.
func peek(count: int = 5) -> Array:
	return _queue.slice(0, count)

# ── Internals ─────────────────────────────────────────────────────────────────

func _draw_one() -> String:
	if _current_bag.is_empty():
		_refill_bag()
	return _current_bag.pop_back()

func _refill_bag() -> void:
	_current_bag = Pieces.PIECE_TYPES.duplicate()
	# Fisher-Yates shuffle
	for i in range(_current_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = _current_bag[i]
		_current_bag[i] = _current_bag[j]
		_current_bag[j] = tmp
