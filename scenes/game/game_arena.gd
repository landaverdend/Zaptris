class_name GameArena
extends Node3D

@export var config: GameArenaConfig

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
	var cfg := config if config else GameArenaConfig.new()
	logic.garbage_enabled = cfg.garbage_enabled
	scoreboard.setup(logic, cfg.show_level, cfg.show_sats)
	_apply_layers(self)

func set_qr_texture(bytes: PackedByteArray) -> void:
	qr_display.show_qr(bytes)

func clear_qr_texture() -> void:
	qr_display.hide_qr()

func add_sats_won(amount: int) -> void:
	scoreboard.add_sats(amount)

func show_loading_qr() -> void:
	qr_display.show_loading()

func set_zap_qr_texture(bytes: PackedByteArray) -> void:
	qr_display.show_qr(bytes)

func _apply_layers(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = RENDER_LAYER
	for child in node.get_children():
		_apply_layers(child)
