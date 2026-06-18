extends Node3D

const ARENA_SCENE        := preload("res://scenes/game/arena/game_arena.tscn")
const LOBBY_CARD_SCENE   := preload("res://scenes/modes/local/lobby_card.tscn")
const ROUTER_SCRIPT      := preload("res://scenes/modes/local/input_router.gd")
const LOCAL_RULES_SCRIPT := preload("res://scenes/modes/local/local_rules.gd")
const COUNTDOWN_SCRIPT   := preload("res://scenes/game/logic/countdown_timer.gd")

const MIN_PLAYERS := 2
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
	var attack_sats:        int   = 5     # invoice amount for routing reliability
	var attack_lines:       int   = 5      # garbage lines sent per attack (decoupled from sats)

var config := MatchConfig.new()

# ── Per-player slot ────────────────────────────────────────────────────────────

class PlayerSlot:
	var arena:             Node3D
	var card:              Node
	var paid:              bool   = false
	var lightning_address: String = ""

# ── State ──────────────────────────────────────────────────────────────────────

enum State { LOBBY, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }
var state   := State.LOBBY
var players: Array[PlayerSlot] = []
var arena_count: int = 2

## Which player indices have received their QR code (lobby pre-creation).
var _qr_ready: Array[bool] = []

## Total sats in the pot. Decremented as sats stream out during gameplay.
var pot_sats:     int = 0
## Locked in at game start — payout amount is derived from this, not live pot_sats.
var starting_pot: int = 0
## Sats paid out per tick, computed once at game start.
var sats_per_tick: int = 0
## Player index that triggered the last pay_winner call; -1 if none pending.
var _last_tick_winner: int = -1

# ── Logic nodes ────────────────────────────────────────────────────────────────

var router: Node           = null
var local_rules: Node      = null
var countdown_timer: Node  = null
var payment_timer: Timer   = null
var payment_service: PaymentService = null

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var add_button: Button         = $UILayer/PlayerControls/AddButton
@onready var remove_button: Button      = $UILayer/PlayerControls/RemoveButton
@onready var count_label: Label         = $UILayer/PlayerControls/CountLabel
@onready var lobby_layer: Control       = $UILayer/LobbyLayer
@onready var countdown_overlay: Control = $UILayer/CountdownOverlay
@onready var countdown_label: Label     = $UILayer/CountdownOverlay/Label
@onready var pot_amount_3d: Label3D     = $Pot/Amount
@onready var _pot_zaps: Array[Node3D]   = [$Pot/LightningZap, $Pot/LightningZap2]
@onready var debug_panel: Control       = $UILayer/DebugGarbage
@onready var _dbg_lines_label: Label    = $UILayer/DebugGarbage/VBox/AmountRow/LinesLabel
@onready var _nwc_label: Label          = $UILayer/NWCStatus

var _dbg_lines: int = 4

# dev_id → arena_index, populated one frame after join so the join press
# itself doesn't immediately trigger Ready.
var _controller_slots: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	payment_service = PaymentService.new()
	payment_service.name = "PaymentService"
	payment_service.nwc_ready.connect(_on_nwc_ready)
	add_child(payment_service)
	payment_service.invoice_qr_ready.connect(_on_invoice_qr_ready)
	payment_service.garbage_attack.connect(_on_garbage_attack)
	payment_service.payment_received.connect(_on_payment_received)
	payment_service.address_checked.connect(_on_address_checked)
	payment_service.payment_settled.connect(_on_payment_settled)

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
	$UILayer/DebugGarbage/VBox/ZapButton.pressed.connect(_play_pot_zaps)
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

func _on_device_joined(arena_index: int, device_label: String, source: int, dev_id: int) -> void:
	if arena_index < players.size():
		players[arena_index].card.set_device(device_label)
		if source == PlayerInput.InputSource.CONTROLLER:
			call_deferred("_register_controller", dev_id, arena_index)
			call_deferred("_focus_controller_ready", arena_index)

func _register_controller(dev_id: int, arena_index: int) -> void:
	_controller_slots[dev_id] = arena_index

func _focus_controller_ready(arena_index: int) -> void:
	if arena_index < players.size():
		players[arena_index].card.focus_ready_btn()

# Use _input (fires before GUI) so we consume the event before Godot's
# native button focus system also processes it — prevents double-fire.
func _input(event: InputEvent) -> void:
	if state != State.LOBBY:
		return
	if not (event is InputEventJoypadButton) or not (event as InputEventJoypadButton).pressed:
		return
	if not event.is_action_pressed("ui_accept"):
		return
	var dev := (event as InputEventJoypadButton).device
	if dev in _controller_slots:
		get_viewport().set_input_as_handled()
		_on_player_ready(_controller_slots[dev])

## Attack invoice QR ready — show it on the arena so spectators can scan.
func _on_invoice_qr_ready(player_index: int, qr_bytes: PackedByteArray) -> void:
	print("[LocalMode] invoice_qr_ready player=%d bytes=%d" % [player_index, qr_bytes.size()])
	if player_index < _qr_ready.size():
		_qr_ready[player_index] = true
	_nwc_label.text     = "NWC ⚡ ONLINE"
	_nwc_label.modulate = Color(0.3, 1.0, 0.4, 1)
	if player_index >= players.size(): return
	players[player_index].arena.set_zap_qr_texture(qr_bytes)

## Spectator paid an attack invoice — send garbage to that player.
func _on_garbage_attack(player_index: int, amount_sats: int) -> void:
	if state != State.PLAYING: return
	if player_index < 0 or player_index >= players.size(): return
	_set_pot(pot_sats + amount_sats)
	players[player_index].arena.get_node("GameLogic").receive_garbage(config.attack_lines)
	players[player_index].arena.show_loading_qr()

## Any payment confirmed received — zap the pot regardless of what it triggers.
func _on_payment_received(_player_index: int, _amount_sats: int) -> void:
	if state == State.PLAYING:
		_play_pot_zaps()

func _play_pot_zaps() -> void:
	for zap in _pot_zaps:
		zap.play()

func _on_check_pressed(index: int) -> void:
	var address: String = players[index].card.get_lightning_address()
	if address.is_empty(): return
	players[index].lightning_address = address
	payment_service.check_address(index, address)

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
	_controller_slots.clear()
	router.stop_listening()
	local_rules.reset_ready()
	if payment_service:
		payment_service.clear_invoices()
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
		cfg.show_sats       = arena_count > 1

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
			slot.paid = players[i].paid

		if not config.free_mode:
			slot.card.set_requires_payment()
			if slot.paid:
				slot.card.show_paid()
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

	# Pre-create attack invoices so the relay has time to connect before game start.
	_qr_ready.resize(arena_count)
	_qr_ready.fill(false)
	if arena_count > 1:
		payment_service.start_attack_invoices(arena_count, config.attack_sats)

	_update_camera()
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
	print("[LocalMode] _on_all_ready")
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
	print("[LocalMode] _begin_play arena_count=%d" % arena_count)
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

	if arena_count > 1:
		for i in range(players.size()):
			if i >= _qr_ready.size() or not _qr_ready[i]:
				players[i].arena.show_loading_qr()

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

	payment_service.clear_invoices()
	var winner: PlayerSlot = players[winner_index]
	if pot_sats > 0 and not winner.lightning_address.is_empty():
		payment_service.pay_pot_remainder(winner.lightning_address, pot_sats)
		_set_pot(0)

	countdown_label.text = "Player %d\nWins the Match!" % (winner_index + 1)
	countdown_overlay.show()
	await get_tree().create_timer(5.0).timeout
	_reset_match()

func _reset_match() -> void:
	_controller_slots.clear()
	local_rules.setup(arena_count)
	var new_seed := randi()
	for slot: PlayerSlot in players:
		slot.arena.process_mode = Node.PROCESS_MODE_PAUSABLE
		slot.arena.get_node("GameLogic").reset(new_seed)
		slot.card.reset_ready_button()
	_reset_payments()
	_update_pot()
	if arena_count > 1:
		_qr_ready.fill(false)
		payment_service.start_attack_invoices(arena_count, config.attack_sats)
	countdown_overlay.hide()
	lobby_layer.show()
	$UILayer/PlayerControls.show()
	router.start_listening(players.map(func(s: PlayerSlot) -> Node3D: return s.arena))
	state = State.LOBBY

func _reset_payments() -> void:
	payment_service.clear_invoices()
	for slot: PlayerSlot in players:
		slot.paid = config.free_mode
		slot.card.reset_payment()
		slot.arena.clear_qr_texture()

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
	_last_tick_winner = winner_idx
	payment_service.pay_winner(slot.lightning_address, amount)
	_set_pot(pot_sats - amount)

func _on_payment_settled(amount: int, success: bool) -> void:
	if success and _last_tick_winner >= 0 and _last_tick_winner < players.size():
		players[_last_tick_winner].arena.add_sats_won(amount)
	_last_tick_winner = -1
	if not success:
		push_warning("[payment] failed for %d sats — pot already decremented" % amount)

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

# ── NWC status ────────────────────────────────────────────────────────────────

func _on_nwc_ready(online: bool) -> void:
	if online:
		_nwc_label.text     = "NWC ◌ CONNECTING..."
		_nwc_label.modulate = Color(1.0, 0.85, 0.1, 1)
	else:
		_nwc_label.text     = "NWC ○ OFFLINE"
		_nwc_label.modulate = Color(0.45, 0.45, 0.45, 1)

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
