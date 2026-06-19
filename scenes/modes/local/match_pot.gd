class_name MatchPot
extends Node3D

## Owns the match pot's sats total, the leader-payout tick/settle cycle, and
## both "money moved" effects (zap on attack payment, stream-to-winner on
## payout) — pulled out of local_mode.gd so that file isn't also the one
## deciding when to instantiate visual effects. This node IS the pot
## visually (attached to the existing $Pot Frame instance), so its own
## global_position is already the correct "from" point for effects.

signal pot_changed(new_sats: int)

const SATS_STREAM_SCENE := preload("res://scenes/game/effects/sats_stream.tscn")

@onready var _amount_label: Label3D  = $Amount
@onready var _zaps: Array[Node3D]    = [$LightningZap, $LightningZap2]

var sats: int = 0

var _service: PaymentService
var _payment_timer: Timer

var _sats_per_tick: int = 0
## Callable -> Variant. Returns null (no eligible leader — tied, or no
## address set) or {arena: Node3D, address: String} for whoever's currently
## leading. Supplied by whoever calls start_payouts(); kept generic so this
## class never needs to know about local_mode's player-slot structure.
var _leader_lookup: Callable = Callable()

## Set while a leader payout is awaiting settlement — also re-entrancy guard
## so a slow/retrying payment can't be double-triggered by the next tick.
var _pending_leader_arena: Node3D = null

func setup(service: PaymentService) -> void:
	_service = service
	_service.payment_settled.connect(_on_payment_settled)

	_payment_timer = Timer.new()
	_payment_timer.one_shot = false
	_payment_timer.timeout.connect(_on_payment_tick)
	add_child(_payment_timer)

# ── Public API ────────────────────────────────────────────────────────────────

func reset(amount: int) -> void:
	_set_sats(amount)

## Attack invoice confirmed paid — grow the pot and play the zap. Caller
## (local_mode) is responsible for any game-state gating (e.g. don't zap
## while still in the lobby).
func add(amount: int) -> void:
	_set_sats(sats + amount)
	play_pot_zap()

func play_pot_zap() -> void:
	for zap in _zaps:
		zap.play()

func start_payouts(payout_percent: float, payout_interval: float, leader_lookup: Callable) -> void:
	_sats_per_tick = max(1, int(sats * payout_percent))
	_leader_lookup = leader_lookup
	_pending_leader_arena = null
	_payment_timer.wait_time = payout_interval
	_payment_timer.start()

func stop_payouts() -> void:
	_payment_timer.stop()

## Pay whatever's left to the match winner — bypasses the tick/settle cycle
## above entirely (mirrors RustBridge.pay_pot_remainder not checking the
## in-flight guard pay_winner does).
func pay_remainder(address: String) -> void:
	if sats > 0 and not address.is_empty():
		_service.pay_pot_remainder(address, sats)
		_set_sats(0)

## Debug-only: play the stream effect to an arbitrary arena without going
## through a real payment.
func debug_stream_to(arena: Node3D) -> void:
	_play_stream_to(arena.sats_box.global_position)

# ── Tick / settle ─────────────────────────────────────────────────────────────

func _on_payment_tick() -> void:
	if sats <= 0 or _pending_leader_arena != null:
		return  # nothing to pay out, or a previous payout is still settling
	if not _leader_lookup.is_valid():
		return
	var leader = _leader_lookup.call()
	if leader == null:
		return
	var amount: int = mini(_sats_per_tick, sats)
	_pending_leader_arena = leader.arena
	_service.pay_winner(leader.address, amount)

func _on_payment_settled(amount: int, success: bool) -> void:
	# Pot only moves once the payment is actually confirmed — moving it
	# eagerly at tick time would desync the visible pot from whether the
	# sats really went anywhere (and from the stream effect below).
	if success and _pending_leader_arena != null:
		_set_sats(sats - amount)
		_pending_leader_arena.add_sats_won(amount)
		_play_stream_to(_pending_leader_arena.sats_box.global_position)
	elif not success:
		push_warning("[MatchPot] payout of %d sats failed — pot unaffected, will retry next tick" % amount)
	_pending_leader_arena = null

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_sats(value: int) -> void:
	sats = value
	_amount_label.text = "⚡ %d" % sats
	pot_changed.emit(sats)

func _play_stream_to(target: Vector3) -> void:
	var stream := SATS_STREAM_SCENE.instantiate()
	add_child(stream)
	stream.play_between(global_position, target)
