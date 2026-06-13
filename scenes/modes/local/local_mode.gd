extends Node3D

const ARENA_SCENE        := preload("res://scenes/game/game_arena.tscn")
const LOBBY_CARD_SCENE   := preload("res://scenes/modes/local/lobby_card.tscn")
const ROUTER_SCRIPT      := preload("res://scenes/modes/local/input_router.gd")
const LOCAL_RULES_SCRIPT := preload("res://scenes/modes/local/local_rules.gd")
const COUNTDOWN_SCRIPT   := preload("res://scenes/game/countdown_timer.gd")

const MIN_PLAYERS := 1
const MAX_PLAYERS := 4

# 3D layout — world-space units between arena origins.
# Each arena occupies roughly x=[-3, 16.5] (hold box to queue edge),
# so 22 units of spacing leaves a ~2.5-unit gap between panels.
const ARENA_SPACING := 22.0

# ── Config ─────────────────────────────────────────────────────────────────────

class MatchConfig:
	var free_mode:          bool  = true
	var buy_in_sats:        int   = 25
	var free_pot_sats:      int   = 100
	var payout_percent:     float = 0.05   # fraction of starting pot paid out per tick
	var payout_interval:    float = 10.0   # seconds between payouts

var config := MatchConfig.new()

# ── Per-player slot ────────────────────────────────────────────────────────────

class PlayerSlot:
	var arena:             Node3D
	var card:              Node
	var paid:              bool            = false
	var qr_bytes:          PackedByteArray = PackedByteArray()
	var lightning_address: String          = ""

# ── State ──────────────────────────────────────────────────────────────────────

enum State { LOBBY, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }
var state   := State.LOBBY
var players: Array[PlayerSlot] = []
var arena_count: int = 1

## Total sats in the pot. Decremented as sats stream out during gameplay.
var pot_sats:     int = 0
## Locked in at game start — payout amount is derived from this, not live pot_sats.
var starting_pot: int = 0
## Sats paid out per tick, computed once at game start.
var sats_per_tick: int = 0

# ── Logic nodes ────────────────────────────────────────────────────────────────

var router: Node          = null
var local_rules: Node     = null
var countdown_timer: Node = null
var payment_timer: Timer  = null
var bridge: Node          = null

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var add_button: Button         = $UILayer/PlayerControls/AddButton
@onready var remove_button: Button      = $UILayer/PlayerControls/RemoveButton
@onready var count_label: Label         = $UILayer/PlayerControls/CountLabel
@onready var lobby_layer: Control       = $UILayer/LobbyLayer
@onready var countdown_overlay: Control = $UILayer/CountdownOverlay
@onready var countdown_label: Label     = $UILayer/CountdownOverlay/Label
@onready var pot_amount_3d: Label3D     = $Pot/Amount
@onready var debug_panel: Control       = $UILayer/DebugGarbage
@onready var _dbg_lines_label: Label    = $UILayer/DebugGarbage/VBox/AmountRow/LinesLabel

var _dbg_lines: int = 4
var _zap_qr_bytes: PackedByteArray = PackedByteArray()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	bridge = RustBridge.new()
	bridge.name = "RustBridge"
	add_child(bridge)
	bridge.invoice_ready.connect(_on_invoice_ready)
	bridge.invoice_paid.connect(_on_invoice_paid)
	bridge.address_checked.connect(_on_address_checked)
	bridge.payment_settled.connect(_on_payment_settled)
	bridge.zap_received.connect(_on_zap_received)
	bridge.zap_qr_ready.connect(_on_zap_qr_ready)

	bridge.setup_zap_qr()

	var poll_timer := Timer.new()
	poll_timer.wait_time = 1.0
	poll_timer.autostart = true
	poll_timer.timeout.connect(bridge.poll)
	add_child(poll_timer)

	countdown_timer = COUNTDOWN_SCRIPT.new()
	countdown_timer.name = "CountdownTimer"
	add_child(countdown_timer)
	countdown_timer.finished.connect(_on_countdown_finished)

	payment_timer = Timer.new()
	payment_timer.one_shot = false
	payment_timer.autostart = false
	payment_timer.timeout.connect(_on_payment_tick)
	add_child(payment_timer)

	$UILayer/DebugGarbage/VBox/AmountRow/DecButton.pressed.connect(_on_dbg_dec)
	$UILayer/DebugGarbage/VBox/AmountRow/IncButton.pressed.connect(_on_dbg_inc)
	$UILayer/DebugGarbage/VBox/SendButton.pressed.connect(_on_dbg_send)
	_dbg_lines_label.text = str(_dbg_lines)

	router = ROUTER_SCRIPT.new()
	router.name = "InputRouter"
	add_child(router)
	router.device_joined.connect(_on_device_joined)

	local_rules = LOCAL_RULES_SCRIPT.new()
	local_rules.name = "LocalRules"
	add_child(local_rules)
	local_rules.all_ready.connect(_on_all_ready)
	local_rules.round_over.connect(_on_round_over)
	local_rules.match_over.connect(_on_match_over)

	add_button.pressed.connect(_on_add_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	_respawn()

# ── Lobby controls ────────────────────────────────────────────────────────────

func _on_add_pressed() -> void:
	if arena_count >= MAX_PLAYERS: return
	arena_count += 1
	_respawn()

func _on_remove_pressed() -> void:
	if arena_count <= MIN_PLAYERS: return
	arena_count -= 1
	_respawn()

func _on_device_joined(arena_index: int, device_label: String) -> void:
	if arena_index < players.size():
		players[arena_index].card.set_device(device_label)

func _on_invoice_ready(player_index: int, qr_bytes: PackedByteArray) -> void:
	if player_index >= players.size(): return
	var slot: PlayerSlot = players[player_index]
	slot.qr_bytes = qr_bytes
	slot.card.set_qr(qr_bytes)
	slot.arena.set_qr_texture(qr_bytes)

func _on_invoice_paid(player_index: int) -> void:
	if player_index >= players.size(): return
	var slot: PlayerSlot = players[player_index]
	slot.paid = true
	slot.card.show_paid()
	slot.arena.clear_qr_texture()

func _on_check_pressed(index: int) -> void:
	var address: String = players[index].card.get_lightning_address()
	if address.is_empty(): return
	players[index].lightning_address = address
	bridge.check_lightning_address(index, address)

func _on_address_checked(player_index: int, is_valid: bool, message: String) -> void:
	if player_index < players.size():
		players[player_index].card.show_address_result(is_valid, message)

func _on_player_ready(index: int) -> void:
	players[index].card.show_ready()
	local_rules.set_ready(index)

# ── Spawn / clear ─────────────────────────────────────────────────────────────

func _respawn() -> void:
	_clear_arenas()
	_spawn_arenas()
	_update_buttons()
	_update_pot()

func _clear_arenas() -> void:
	router.stop_listening()
	local_rules.reset_ready()
	# Slots are rebuilt below but payment state (paid, qr_bytes) is preserved
	# in the new slots — only _reset_payments() wipes it (on match end).
	for slot in players:
		slot.arena.queue_free()
		slot.card.queue_free()
	players.clear()

func _spawn_arenas() -> void:
	local_rules.setup(arena_count)

	# Scale arenas so all N fit on screen, then re-centre around the camera's X=6.75.
	# Arena content spans local x=[-3, 16.5] (centre = 6.75), so the scaled world
	# centre of arena i is: position.x + 6.75 * s.
	var s  := _compute_arena_scale()
	var p0 := 6.75 * (1.0 - s) + ARENA_SPACING * s * (1.0 - arena_count) / 2.0

	for i in range(arena_count):
		var slot := PlayerSlot.new()

		var cfg := GameArenaConfig.new()
		cfg.garbage_enabled = true
		cfg.show_level      = false
		cfg.show_qr         = arena_count > 1

		slot.arena = ARENA_SCENE.instantiate()
		slot.arena.config       = cfg
		slot.arena.process_mode = Node.PROCESS_MODE_PAUSABLE
		slot.arena.scale        = Vector3(s, s, s)
		slot.arena.position     = Vector3(p0 + i * ARENA_SPACING * s, 0.0, 0.0)
		add_child(slot.arena)

		slot.card = LOBBY_CARD_SCENE.instantiate()
		lobby_layer.add_child(slot.card)
		slot.card.setup(i + 1)

		# Restore payment state carried over from the previous spawn.
		if i < players.size():
			var prev: PlayerSlot = players[i]
			slot.paid     = prev.paid
			slot.qr_bytes = prev.qr_bytes

		if not config.free_mode:
			slot.card.set_requires_payment()
			if not slot.qr_bytes.is_empty():
				slot.card.set_qr(slot.qr_bytes)
				slot.arena.set_qr_texture(slot.qr_bytes)
			if slot.paid:
				slot.card.show_paid()
				slot.arena.clear_qr_texture()
			elif i >= players.size():  # genuinely new slot
				bridge.create_player_invoice(i, config.buy_in_sats)
		else:
			slot.paid = true

		var idx := i
		slot.card.ready_pressed.connect(func(): _on_player_ready(idx))
		slot.card.check_pressed.connect(func(): _on_check_pressed(idx))

		players.append(slot)

	# Drop any slots beyond the new count (player was removed).
	while players.size() > arena_count:
		players.pop_back()

	router.start_listening(players.map(func(s: PlayerSlot) -> Node3D: return s.arena))
	_update_camera()
	if not _zap_qr_bytes.is_empty():
		for slot: PlayerSlot in players:
			slot.arena.set_zap_qr_texture(_zap_qr_bytes)
	_position_lobby_cards.call_deferred()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _update_buttons() -> void:
	count_label.text       = "%d Players" % arena_count
	add_button.disabled    = arena_count >= MAX_PLAYERS
	remove_button.disabled = arena_count <= MIN_PLAYERS

func _update_pot() -> void:
	_set_pot(config.free_pot_sats if config.free_mode else config.buy_in_sats * arena_count)

func _set_pot(value: int) -> void:
	pot_sats            = value
	pot_amount_3d.text  = "⚡ %d" % pot_sats

func _position_lobby_cards() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for i in range(players.size()):
		var ax: float = players[i].arena.position.x
		var s: float  = players[i].arena.scale.x
		var pts: Array[Vector2] = [
			camera.unproject_position(Vector3(ax + 0.045  * s, 0.0,       -0.665 * s)),
			camera.unproject_position(Vector3(ax + 0.045  * s, 20.0 * s,  -0.665 * s)),
			camera.unproject_position(Vector3(ax + 10.045 * s, 0.0,       -0.665 * s)),
			camera.unproject_position(Vector3(ax + 10.045 * s, 20.0 * s,  -0.665 * s)),
		]
		var s_min: Vector2 = pts[0]
		var s_max: Vector2 = pts[0]
		for p: Vector2 in pts:
			s_min = s_min.min(p)
			s_max = s_max.max(p)
		players[i].card.position = s_min
		players[i].card.size     = s_max - s_min

func _compute_arena_scale() -> float:
	# 4 players = baseline (1.0). Each player fewer adds a small bump.
	return 1.0 + (MAX_PLAYERS - arena_count) * 0.15

func _update_camera() -> void:
	# Camera is fixed — never move it. Only toggle the ball.
	var bg := get_node_or_null("Background") as Node3D
	if bg == null:
		return
	var ball_body := bg.get_node_or_null("BallBody") as Node3D
	if ball_body:
		ball_body.visible = true

# ── Countdown ─────────────────────────────────────────────────────────────────

func _on_countdown_finished() -> void:
	_begin_play()

func _on_all_ready() -> void:
	if not config.free_mode and not players.all(func(s: PlayerSlot) -> bool: return s.paid):
		return
	state = State.COUNTDOWN
	router.stop_listening()
	lobby_layer.hide()
	$UILayer/PlayerControls.hide()
	countdown_overlay.show()
	countdown_timer.start(countdown_label)

# ── Game start ────────────────────────────────────────────────────────────────

func _begin_play() -> void:
	state = State.PLAYING
	var round_seed := randi()
	for slot: PlayerSlot in players:
		slot.lightning_address = slot.card.get_lightning_address()
		var input: Node = slot.arena.get_node("PlayerInput")
		input.das_frames = slot.card.das_value
		input.arr_frames = slot.card.arr_value
		input.clear_held()
		slot.arena.get_node("GameLogic").reset(round_seed)
		slot.arena.get_node("GameLogic").start()
	local_rules.start_round(players.map(func(s: PlayerSlot) -> Node3D: return s.arena))

	# Lock in the starting pot and derive the per-tick payout once.
	starting_pot  = pot_sats
	sats_per_tick = max(1, int(starting_pot * config.payout_percent))
	payment_timer.wait_time = config.payout_interval
	payment_timer.start()

	await get_tree().create_timer(0.6).timeout
	countdown_overlay.hide()

# ── Round end ─────────────────────────────────────────────────────────────────

func _on_round_over(winner_index: int) -> void:
	state = State.ROUND_END
	payment_timer.stop()
	for slot: PlayerSlot in players:
		slot.arena.process_mode = Node.PROCESS_MODE_DISABLED
	var wins: Array = local_rules.get_wins()
	var score: String = " | ".join(wins.map(func(w): return str(w)))
	countdown_label.text = "Player %d Wins!\n%s" % [winner_index + 1, score]
	countdown_overlay.show()
	await get_tree().create_timer(3.0).timeout
	_start_next_round()

func _on_match_over(winner_index: int) -> void:
	state = State.MATCH_END
	payment_timer.stop()
	for slot: PlayerSlot in players:
		slot.arena.process_mode = Node.PROCESS_MODE_DISABLED

	# Pay the remaining pot to the winner.
	var winner: PlayerSlot = players[winner_index]
	if pot_sats > 0 and not winner.lightning_address.is_empty():
		bridge.pay_pot_remainder(winner.lightning_address, pot_sats)
		_set_pot(0)

	countdown_label.text = "Player %d\nWins the Match!" % (winner_index + 1)
	countdown_overlay.show()
	await get_tree().create_timer(5.0).timeout
	_reset_match()

func _reset_match() -> void:
	local_rules.setup(arena_count)
	var new_seed := randi()
	for slot: PlayerSlot in players:
		slot.arena.process_mode = Node.PROCESS_MODE_PAUSABLE
		slot.arena.get_node("GameLogic").reset(new_seed)
		slot.card.reset_ready_button()
	_reset_payments()
	_update_pot()
	countdown_overlay.hide()
	lobby_layer.show()
	$UILayer/PlayerControls.show()
	router.start_listening(players.map(func(s: PlayerSlot) -> Node3D: return s.arena))
	state = State.LOBBY

func _reset_payments() -> void:
	bridge.clear_pending_invoices()
	for i in range(players.size()):
		var slot: PlayerSlot = players[i]
		slot.paid     = config.free_mode
		slot.qr_bytes = PackedByteArray()
		slot.card.reset_payment()
		slot.arena.clear_qr_texture()
		if not config.free_mode:
			bridge.create_player_invoice(i, config.buy_in_sats)

func _start_next_round() -> void:
	for slot: PlayerSlot in players:
		slot.arena.process_mode = Node.PROCESS_MODE_PAUSABLE
		slot.arena.get_node("GameLogic").reset(randi())
	local_rules.reset_ready()
	lobby_layer.hide()
	countdown_overlay.show()
	state = State.COUNTDOWN
	countdown_timer.start(countdown_label)

# ── Payment tick ──────────────────────────────────────────────────────────────

func _on_payment_tick() -> void:
	if state != State.PLAYING or pot_sats <= 0:
		return
	var winner_idx := _highest_scorer()
	if winner_idx < 0:
		return  # tied — no payment until someone pulls ahead
	var slot: PlayerSlot = players[winner_idx]
	if slot.lightning_address.is_empty():
		return
	var amount := mini(sats_per_tick, pot_sats)
	bridge.pay_winner(slot.lightning_address, amount)
	_set_pot(pot_sats - amount)

func _on_payment_settled(amount: int, success: bool) -> void:
	if not success:
		push_warning("[payment] failed for %d sats — pot already decremented" % amount)

func _on_zap_received(player_index: int, amount_sats: int, command: String) -> void:
	if state != State.PLAYING:
		return
	if player_index < 0 or player_index >= players.size():
		return
	# Inbound sats always go into the pot — bystanders are funding the prize pool.
	_set_pot(pot_sats + amount_sats)
	match command:
		"GARBAGE":
			# 1 line of garbage per sat, up to 15.
			var lines := clampi(amount_sats, 1, 15)
			players[player_index].arena.get_node("GameLogic").receive_garbage(lines)

# ── Zap QR ────────────────────────────────────────────────────────────────────

## Called by the bridge once it has fetched nostrPubkey from LNURL and
## generated the nostr:npub1… QR. Displays it in the top-right corner.
func _on_zap_qr_ready(qr_bytes: PackedByteArray) -> void:
	_zap_qr_bytes = qr_bytes
	for slot: PlayerSlot in players:
		slot.arena.set_zap_qr_texture(qr_bytes)

## Returns the index of the sole leader, or -1 if scores are tied.
func _highest_scorer() -> int:
	var best_idx   := -1
	var best_score := -1
	var tied       := false
	for i in range(players.size()):
		var logic := players[i].arena.get_node("GameLogic") as GameLogic
		var score: int = logic.score if logic else 0
		if score > best_score:
			best_score = score
			best_idx   = i
			tied       = false
		elif score == best_score:
			tied = true
	return -1 if tied else best_idx

# ── Debug ─────────────────────────────────────────────────────────────────────

func _on_dbg_dec() -> void:
	_dbg_lines = max(1, _dbg_lines - 1)
	_dbg_lines_label.text = str(_dbg_lines)

func _on_dbg_inc() -> void:
	_dbg_lines = min(20, _dbg_lines + 1)
	_dbg_lines_label.text = str(_dbg_lines)

func _on_dbg_send() -> void:
	if players.is_empty(): return
	players[0].arena.get_node("GameLogic").receive_garbage(_dbg_lines)
