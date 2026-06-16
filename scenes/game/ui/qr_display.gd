@tool
class_name QRDisplay
extends Node3D

@onready var qr_sprite:     Sprite3D = $QRSprite
@onready var action_label:  Label3D  = $ActionLabel
@onready var scan_label:    Label3D  = $ScanLabel
@onready var loading_label: Label3D  = $LoadingLabel

@export_group("Display Text")
@export var action_text: String = "⚡ PAY TO ATTACK":
	set(v):
		action_text = v
		if action_label:
			action_label.text = v

@export var scan_text: String = "SCAN TO ATTACK":
	set(v):
		scan_text = v
		if scan_label:
			scan_label.text = v

@export_group("Colors")
@export var action_color: Color = Color(1, 1, 0, 1):
	set(v):
		action_color = v
		if action_label:
			action_label.modulate = v

@export var scan_color: Color = Color(1, 1, 1, 1):
	set(v):
		scan_color = v
		if scan_label:
			scan_label.modulate = v

var _loading := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	visible = false

func _process(_delta: float) -> void:
	if _loading:
		loading_label.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)

func show_loading() -> void:
	_loading = true
	qr_sprite.visible    = false
	qr_sprite.texture    = null
	scan_label.visible   = false
	loading_label.visible = true
	visible = true

func show_qr(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	_loading = false
	var img := Image.new()
	img.load_png_from_buffer(bytes)
	qr_sprite.texture     = ImageTexture.create_from_image(img)
	action_label.text     = action_text
	action_label.modulate = action_color
	scan_label.text       = scan_text
	scan_label.modulate   = scan_color
	qr_sprite.visible     = true
	scan_label.visible    = true
	loading_label.visible = false
	visible = true

func hide_qr() -> void:
	_loading = false
	visible = false
	qr_sprite.texture    = null
	loading_label.visible = false
