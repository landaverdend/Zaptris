extends Control

var das_value: float = 12.0
var arr_value: float = 2.0
var player_num: int = 1
var requires_payment: bool = false
var _controller_device: bool = false
var _keyboard_open: bool = false

# The field's width as a fraction of the card's own size, so it scales with
# however small the card gets at higher player counts instead of fighting
# CenterContainer with a fixed pixel value.
const FIELD_WIDTH_RATIO := 0.8
const FIELD_MIN_WIDTH   := 140.0

@onready var lightning: LineEdit    = $CenterContainer/VBox/LightningEdit
@onready var address_status: Label  = $CenterContainer/VBox/AddressStatus
@onready var qr_rect: TextureRect   = $CenterContainer/VBox/QRRect
@onready var player_label: Label    = $CenterContainer/VBox/PlayerLabel
@onready var check_btn: Button      = $CenterContainer/VBox/CheckButton
@onready var ready_btn: Button      = $CenterContainer/VBox/ReadyButton
@onready var keyboard: Control      = $OnscreenKeyboard

signal ready_pressed
signal check_pressed

func _ready() -> void:
	ready_btn.pressed.connect(func(): ready_pressed.emit())
	check_btn.pressed.connect(func(): check_pressed.emit())
	lightning.gui_input.connect(_on_lightning_gui_input)
	keyboard.closed.connect(_on_keyboard_closed)
	_configure_focus()
	_update_lightning_width()

# LocalMode resizes this card per-player based on arena scale (smaller at
# higher player counts) — keep the field's width proportional to that.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not _keyboard_open:
		_update_lightning_width()

func _update_lightning_width() -> void:
	lightning.custom_minimum_size.x = max(FIELD_MIN_WIDTH, size.x * FIELD_WIDTH_RATIO)

# Controller players can't type directly — opening the on-screen keyboard
# on the field they'd otherwise edit with a physical keyboard.
func _on_lightning_gui_input(event: InputEvent) -> void:
	if _controller_device and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_open_keyboard()

func _open_keyboard() -> void:
	_set_card_focusable(false)
	_keyboard_open = true
	# Match the field's width to the keyboard so there's room to actually
	# see what's typed — then wait a frame for the container to re-layout
	# before the keyboard measures the field's (now wider) rect to dock under it.
	lightning.custom_minimum_size.x = keyboard.size.x
	await get_tree().process_frame
	keyboard.open(lightning)

func _on_keyboard_closed() -> void:
	_set_card_focusable(true)
	_keyboard_open = false
	_update_lightning_width()
	lightning.grab_focus()

# While the keyboard is open, nothing else on the card should be reachable —
# otherwise focus could wander out of the keyboard via d-pad navigation.
func _set_card_focusable(enabled: bool) -> void:
	var mode := Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	lightning.focus_mode = mode
	ready_btn.focus_mode = mode
	check_btn.focus_mode = mode
	if enabled:
		_configure_focus()

func _configure_focus() -> void:
	lightning.focus_mode = Control.FOCUS_ALL
	check_btn.focus_mode = Control.FOCUS_ALL
	ready_btn.focus_mode = Control.FOCUS_ALL

	lightning.focus_neighbor_left = NodePath(".")
	lightning.focus_neighbor_right = NodePath(".")
	lightning.focus_neighbor_top = lightning.get_path_to(ready_btn)
	lightning.focus_neighbor_bottom = lightning.get_path_to(check_btn)
	lightning.focus_previous = lightning.get_path_to(ready_btn)
	lightning.focus_next = lightning.get_path_to(check_btn)

	check_btn.focus_neighbor_left = NodePath(".")
	check_btn.focus_neighbor_right = NodePath(".")
	check_btn.focus_neighbor_top = check_btn.get_path_to(lightning)
	check_btn.focus_neighbor_bottom = check_btn.get_path_to(ready_btn)
	check_btn.focus_previous = check_btn.get_path_to(lightning)
	check_btn.focus_next = check_btn.get_path_to(ready_btn)

	ready_btn.focus_neighbor_left = NodePath(".")
	ready_btn.focus_neighbor_right = NodePath(".")
	ready_btn.focus_neighbor_top = ready_btn.get_path_to(check_btn)
	ready_btn.focus_neighbor_bottom = ready_btn.get_path_to(lightning)
	ready_btn.focus_previous = ready_btn.get_path_to(check_btn)
	ready_btn.focus_next = ready_btn.get_path_to(lightning)

func setup(num: int) -> void:
	player_num        = num
	player_label.text = "Player %d" % player_num
	$CenterContainer/VBox/DeviceLabel.text = "Waiting to join..."
	# Always editable — only the keyboard can type text regardless of which
	# device claims this slot, so gating it per-device just blocks the
	# keyboard player from filling in addresses for controller players.
	lightning.editable = true

## Lock the Ready button until the buy-in invoice is confirmed paid.
func set_requires_payment() -> void:
	requires_payment    = true
	ready_btn.disabled  = true

## Called when the Rust watch thread confirms the buy-in invoice is settled.
func show_paid() -> void:
	qr_rect.hide()
	player_label.text  = "Player %d\n⚡ Paid!" % player_num
	ready_btn.disabled = false

## Reset payment state for the next match.
func reset_payment() -> void:
	qr_rect.hide()
	qr_rect.texture    = null
	player_label.text  = "Player %d" % player_num
	ready_btn.disabled = requires_payment  # re-lock only if buy-in mode

func show_ready() -> void:
	ready_btn.text     = "READY!"
	ready_btn.disabled = true

func reset_ready_button() -> void:
	ready_btn.text     = "Ready?"
	ready_btn.disabled = requires_payment  # respect payment gate on reset

## Called by LocalMode when the bridge emits address_checked.
func show_address_result(is_valid: bool, message: String) -> void:
	address_status.text = message if is_valid else "Unable to find address"
	address_status.modulate = Color.GREEN if is_valid else Color.RED
	address_status.show()

# Called by LocalMode when InputRouter assigns a device to this slot.
func set_device(device_label: String) -> void:
	$CenterContainer/VBox/DeviceLabel.text = device_label
	_controller_device = (device_label != "Keyboard")

func set_qr(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var img := Image.new()
	img.load_png_from_buffer(bytes)
	qr_rect.texture = ImageTexture.create_from_image(img)
	qr_rect.show()

func focus_ready_btn() -> void:
	ready_btn.grab_focus()

# ── Accessor for LocalMode ────────────────────────────────────────────────────

func get_lightning_address() -> String:
	return lightning.text
