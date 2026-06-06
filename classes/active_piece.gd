class_name ActivePiece extends RefCounted

var kind: String = ""
var rotation: int = 0
var row: int = 0
var col: int = 0
var is_floored: bool = false
var time_on_floor: int = 0
var highest_row: int = 0
var total_resets: int = 0
var last_action_was_rotation: bool = false
var just_spawned: bool = true

func copy() -> ActivePiece:
	var p = ActivePiece.new()
	p.kind = kind
	p.rotation = rotation
	p.row = row
	p.col = col
	p.is_floored = is_floored
	p.time_on_floor = time_on_floor
	p.highest_row = highest_row
	p.total_resets = total_resets
	p.last_action_was_rotation = last_action_was_rotation
	p.just_spawned = just_spawned
	return p
