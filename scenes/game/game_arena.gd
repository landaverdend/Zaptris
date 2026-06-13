class_name GameArena
extends Node3D

@export var cell_size: float = 1.0
@export var bag_seed: int = -1
@export var show_level: bool = true
@export var garbage_enabled: bool = false:
	set(value):
		garbage_enabled = value
		# logic is null before _ready(); propagation happens there too.
		if logic:
			logic.garbage_enabled = value

@onready var logic: Node         = $GameLogic
@onready var board: Node3D       = $Board
@onready var hold_box: Node3D    = $HoldBox
@onready var piece_queue: Node3D = $PieceQueue
@onready var scoreboard: Node3D  = $Scoreboard
@onready var qr_display: Node3D  = $QRDisplay

# Render layer 3 = arena.  ArenaLight's cull mask targets only this layer
# so it won't bleed into the background.
const RENDER_LAYER := 5  # bits: layer 1 + layer 3

func _ready() -> void:
	logic.garbage_enabled = garbage_enabled
	scoreboard.setup(logic, show_level)
	_apply_layers(self)

func set_qr_texture(bytes: PackedByteArray) -> void:
	qr_display.show_qr(bytes, "⚡ BUY IN", "SCAN TO JOIN")

func clear_qr_texture() -> void:
	qr_display.hide_qr()

func set_zap_qr_texture(bytes: PackedByteArray) -> void:
	qr_display.show_qr(bytes, "⚡ ZAP TO ATTACK", "SCAN TO ATTACK")

func _apply_layers(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = RENDER_LAYER
	for child in node.get_children():
		_apply_layers(child)
