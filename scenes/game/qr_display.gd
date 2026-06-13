class_name QRDisplay
extends Node3D

@onready var qr_sprite: Sprite3D   = $QRSprite
@onready var action_label: Label3D = $ActionLabel
@onready var scan_label: Label3D   = $ScanLabel

func _ready() -> void:
	visible = false

## Show a QR code with styled labels.
## action_text → top label  (e.g. "⚡ BUY IN" / "⚡ ZAP TO ATTACK")
func show_qr(bytes: PackedByteArray, action_text: String, scan_text: String) -> void:
	if bytes.is_empty():
		return
	var img := Image.new()
	img.load_png_from_buffer(bytes)
	qr_sprite.texture   = ImageTexture.create_from_image(img)
	action_label.text   = action_text
	scan_label.text     = scan_text
	visible = true

func hide_qr() -> void:
	visible           = false
	qr_sprite.texture = null
