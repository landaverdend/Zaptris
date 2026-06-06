extends Control

var das_value: float = 12.0
var arr_value: float = 2.0
var player_num: int = 1
var requires_payment: bool = false

@onready var das_slider: HSlider    = $CenterContainer/VBox/DASRow/DASSlider
@onready var das_label: Label       = $CenterContainer/VBox/DASRow/DASValue
@onready var arr_slider: HSlider    = $CenterContainer/VBox/ARRRow/ARRSlider
@onready var arr_label: Label       = $CenterContainer/VBox/ARRRow/ARRValue
@onready var lightning: LineEdit    = $CenterContainer/VBox/LightningRow/LightningEdit
@onready var address_status: Label  = $CenterContainer/VBox/AddressStatus
@onready var qr_rect: TextureRect   = $CenterContainer/VBox/QRRect
@onready var player_label: Label    = $CenterContainer/VBox/PlayerLabel
@onready var ready_btn: Button      = $CenterContainer/VBox/ReadyButton

signal ready_pressed
signal check_pressed

func _ready() -> void:
	das_slider.value_changed.connect(_on_das_changed)
	arr_slider.value_changed.connect(_on_arr_changed)
	ready_btn.pressed.connect(func(): ready_pressed.emit())
	$CenterContainer/VBox/LightningRow/CheckButton.pressed.connect(
		func(): check_pressed.emit()
	)

func setup(num: int, board_pos: Vector2, board_size: Vector2) -> void:
	player_num        = num
	position          = board_pos
	size              = board_size
	player_label.text = "Player %d" % player_num
	$CenterContainer/VBox/DeviceLabel.text = "Waiting to join..."
	lightning.editable = false

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
	address_status.text = message
	address_status.modulate = Color.GREEN if is_valid else Color.RED
	address_status.show()

# Called by LocalMode when InputRouter assigns a device to this slot.
func set_device(device_label: String) -> void:
	$CenterContainer/VBox/DeviceLabel.text = device_label
	lightning.editable = (device_label == "Keyboard")

# ── Slider callbacks ──────────────────────────────────────────────────────────

func _on_das_changed(value: float) -> void:
	das_value = value
	das_label.text = "%.1ff" % value

func _on_arr_changed(value: float) -> void:
	arr_value = value
	arr_label.text = "%.1ff" % value

func set_qr(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var img := Image.new()
	img.load_png_from_buffer(bytes)
	qr_rect.texture = ImageTexture.create_from_image(img)
	qr_rect.show()

# ── Accessor for LocalMode ────────────────────────────────────────────────────

func get_lightning_address() -> String:
	return lightning.text
