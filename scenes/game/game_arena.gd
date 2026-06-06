extends Node3D

@export var cell_size: float = 1.0
@export var bag_seed: int = -1
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

func _ready() -> void:
	logic.garbage_enabled = garbage_enabled
