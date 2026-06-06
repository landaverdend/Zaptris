extends Node3D

# Set this before the node enters the scene tree.
# The parent (SoloMode, MultiplayerMode, etc.) is responsible for choosing the
# right size — solo uses the default, multiplayer calculates based on player count.
@export var cell_size: float = 1.0
# Set to a non-negative value to override the random bag seed (e.g. for synced local multiplayer).
# -1 means each arena picks its own random seed in GameLogic._ready().
@export var bag_seed: int = -1
# Enable garbage receive/display — off by default so solo mode needs no changes.
@export var garbage_enabled: bool = false

@onready var logic: Node      = $GameLogic
@onready var board: Node3D    = $Board
@onready var hold_box: Node3D = $HoldBox
@onready var piece_queue: Node3D = $PieceQueue
