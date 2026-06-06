extends Node3D

const WARNING_THRESHOLD = 3  # locked cell within top N visible rows triggers warning

@onready var logic: Node = $"../GameLogic" # the actual game logic.
