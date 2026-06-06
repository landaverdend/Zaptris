extends Node2D

# Set this before the node enters the scene tree.
# The parent (SoloMode, MultiplayerMode, etc.) is responsible for choosing the
# right size — solo uses the default, multiplayer calculates based on player count.
@export var cell_size: int = 36
# Set to a non-negative value to override the random bag seed (e.g. for synced local multiplayer).
# -1 means each arena picks its own random seed in GameLogic._ready().
@export var bag_seed: int = -1
# Enable garbage receive/display — off by default so solo mode needs no changes.
@export var garbage_enabled: bool = false

@onready var logic: Node      = $GameLogic
@onready var board: Node2D    = $Board
@onready var hold_box: Node2D = $HoldBox
@onready var piece_queue: Node2D = $PieceQueue

func _ready() -> void:
	logic.cell_size      = cell_size
	logic.garbage_enabled = garbage_enabled
	if bag_seed >= 0:
		logic.bag = PieceBag.new(bag_seed)
	_layout()

# Position board, hold box, and queue relative to this node's origin.
# Board sits at (0, 0). Hold box extends left, queue extends right.
func _layout() -> void:
	var preview_cell: int = cell_size * 2 / 3
	var board_width: int  = logic.COLS * cell_size
	board.position        = Vector2.ZERO
	hold_box.position     = Vector2(-preview_cell * 4 - 16, 0)
	piece_queue.position  = Vector2(board_width + 16, 0)
