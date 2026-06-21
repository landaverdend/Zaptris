class_name PaymentService
extends Node

## QR bytes ready to display on a player's arena.
signal invoice_qr_ready(player_index: int, qr_bytes: PackedByteArray)
## Spectator paid an attack invoice — apply garbage to that player.
signal garbage_attack(player_index: int, amount_sats: int)
## A payment was confirmed received, regardless of what it's used for.
signal payment_received(player_index: int, amount_sats: int)
## Result of check_address() — for validating payout destinations.
signal address_checked(player_index: int, is_valid: bool, message: String)
## Payout result from pay_winner() / pay_pot_remainder().
signal payment_settled(amount_sats: int, success: bool)
## Fired once after init — true if HOST_NWC was configured successfully.
signal nwc_ready(online: bool)

var _bridge: Node = null
var _attack_sats: int = 15

func _ready() -> void:
	_bridge = RustBridge.new()
	_bridge.name = "RustBridge"
	# Must be set before add_child() — RustBridge reads this in its own
	# ready(), which fires synchronously once it enters the tree below.
	if not Settings.nwc_string.is_empty():
		_bridge.set_nwc_override(Settings.nwc_string)
	add_child(_bridge)
	_bridge.invoice_ready.connect(_on_invoice_ready)
	_bridge.invoice_paid.connect(_on_invoice_paid)
	_bridge.address_checked.connect(_on_address_checked)
	_bridge.payment_settled.connect(_on_payment_settled)

	var poll_timer := Timer.new()
	poll_timer.wait_time = 1.0
	poll_timer.autostart = true
	poll_timer.timeout.connect(_bridge.poll)
	add_child(poll_timer)

	nwc_ready.emit(_bridge.is_nwc_configured())

# ── Public API ────────────────────────────────────────────────────────────────

## Generate fixed-amount attack invoices for all players. Call at game start.
## Each settled payment fires garbage_attack (lines = sats) and auto-cycles.
func start_attack_invoices(player_count: int, sats_per_attack: int) -> void:
	print("[PaymentService] start_attack_invoices count=%d sats=%d" % [player_count, sats_per_attack])
	_attack_sats = sats_per_attack
	_bridge.clear_pending_invoices()
	for i in range(player_count):
		print("[PaymentService] calling create_attack_invoice player=%d sats=%d" % [i, _attack_sats])
		_bridge.create_attack_invoice(i, _attack_sats)

## Stop watching all pending invoices (lobby reset / match end).
func clear_invoices() -> void:
	_bridge.clear_pending_invoices()

## Validate a Lightning address for use as a payout destination.
func check_address(player_index: int, address: String) -> void:
	_bridge.check_lightning_address(player_index, address)

## Stream a per-tick payout to the current leader's Lightning address.
func pay_winner(address: String, amount_sats: int) -> void:
	_bridge.pay_winner(address, amount_sats)

## Pay the remaining pot to the match winner (bypasses in-flight guard).
func pay_pot_remainder(address: String, amount_sats: int) -> void:
	_bridge.pay_pot_remainder(address, amount_sats)

# ── Bridge callbacks ──────────────────────────────────────────────────────────

func _on_invoice_ready(player_index: int, qr_bytes: PackedByteArray) -> void:
	print("[PaymentService] invoice_ready player=%d bytes=%d" % [player_index, qr_bytes.size()])
	invoice_qr_ready.emit(player_index, qr_bytes)

func _on_invoice_paid(player_index: int, amount_sats: int) -> void:
	payment_received.emit(player_index, amount_sats)
	garbage_attack.emit(player_index, amount_sats)
	_bridge.create_attack_invoice(player_index, _attack_sats)

func _on_address_checked(player_index: int, is_valid: bool, message: String) -> void:
	address_checked.emit(player_index, is_valid, message)

func _on_payment_settled(amount_sats: int, success: bool) -> void:
	payment_settled.emit(amount_sats, success)
