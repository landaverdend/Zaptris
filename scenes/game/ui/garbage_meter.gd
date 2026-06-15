extends Node3D

const BLOCK_SCENE := preload("res://scenes/game/ui/garbage_block.tscn")
const MAX_LINES   := 20

@onready var logic:  Node   = $"../GameLogic"
@onready var blocks: Node3D = $Blocks

var _blocks: Array[MeshInstance3D] = []
var _mat:    ShaderMaterial

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	if not logic.garbage_enabled:
		visible = false
		return

	for i in range(MAX_LINES):
		var b: MeshInstance3D = BLOCK_SCENE.instantiate()
		blocks.add_child(b)
		b.position = Vector3(0.0, float(i) * 0.9 + 0.5, 0.0)
		b.visible  = false
		_blocks.append(b)

	_mat = (_blocks[0].get_active_material(0) as ShaderMaterial).duplicate()
	for b in _blocks:
		b.material_override = _mat
	logic.pending_garbage_changed.connect(_on_garbage_changed)

func _process(_delta: float) -> void:
	if _mat == null or not visible or _blocks.is_empty():
		return
	_mat.set_shader_parameter("fill_ratio", logic.get_garbage_urgency())

func _on_garbage_changed(total: int) -> void:
	var count := clampi(total, 0, MAX_LINES)
	for i in range(_blocks.size()):
		var block := _blocks[i]
		if i < count:
			if not block.visible:
				block.scale = Vector3.ZERO
				block.visible = true
				var tw := get_tree().create_tween()
				tw.tween_property(block, "scale", Vector3.ONE, 0.18) \
					.set_delay(i * 0.04) \
					.set_ease(Tween.EASE_OUT) \
					.set_trans(Tween.TRANS_BACK)
		else:
			block.visible = false
			block.scale = Vector3.ONE
