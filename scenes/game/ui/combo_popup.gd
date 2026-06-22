extends Node3D

## Display text per clear type, keyed to ScoreTracker's clear_type strings.
## Colors are pulled from Pieces.COLORS (the same table board.gd uses to
## color the falling pieces) so a clear is tinted like the piece that
## typically makes it — single source of truth, no separate color table.
const _CLEAR_INFO: Dictionary = {
	"single":            { "text": "SINGLE", "color": Color.WHITE },
	"double":            { "text": "DOUBLE", "color": Color.WHITE },
	"triple":            { "text": "TRIPLE", "color": Color.WHITE },
	"tetris":            { "text": "TETRIS!",            "piece": "I" },
	"tspin":             { "text": "T-SPIN",             "piece": "T" },
	"tspin_single":      { "text": "T-SPIN SINGLE",      "piece": "T" },
	"tspin_double":      { "text": "T-SPIN DOUBLE",      "piece": "T" },
	"tspin_triple":      { "text": "T-SPIN TRIPLE",      "piece": "T" },
	"mini_tspin":        { "text": "MINI T-SPIN",        "piece": "T" },
	"mini_tspin_single": { "text": "MINI T-SPIN SINGLE", "piece": "T" },
}

## Which clears count as a "combo" worth a B2B label on the popup — narrower
## than ScoreTracker's own B2B_QUALIFYING (which also awards the bonus to
## tspin_single/mini_tspin_single, but those don't get the "B2B" suffix here).
const _B2B_DISPLAY_TYPES: Array = ["tetris", "tspin_double", "tspin_triple"]

@onready var label: Label3D = $Label

var _tween: Tween

func setup(logic: Node) -> void:
	logic.scorer.clear_scored.connect(_on_clear_scored)
	label.modulate.a = 0.0
	label.outline_modulate.a = 0.0

# Longer strings ("T-SPIN DOUBLE", "MINI T-SPIN SINGLE") would otherwise pop
# to the same peak scale as "TETRIS!" and run off-screen, so scale the peak
# down as text length grows — same idea as score_box.gd's digit-count sizing.
func _peak_scale(text: String) -> float:
	var length := text.length()
	if length > 14:
		return 0.65
	elif length > 10:
		return 0.8
	return 1.0

func _on_clear_scored(clear_type: String, _points: int, was_b2b: bool) -> void:
	var info: Dictionary = _CLEAR_INFO.get(clear_type, {})
	if info.is_empty():
		return

	if _tween:
		_tween.kill()

	var color: Color = info.color if info.has("color") else Pieces.COLORS[info.piece]
	var display_text: String = info.text
	if was_b2b and clear_type in _B2B_DISPLAY_TYPES:
		display_text += " B2B"
	var peak: float = _peak_scale(display_text)

	label.text = display_text
	label.modulate = Color(color, 1.0)
	label.outline_modulate.a = 1.0
	scale = Vector3.ONE * peak * 0.3

	_tween = get_tree().create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3.ONE * peak, 0.75) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fill and outline fade together — Label3D's outline_modulate is a
	# separate property from modulate, so both need tweening or the
	# outline silhouette is left behind after the fill fades out.
	_tween.tween_property(label, "modulate:a", 0.0, 0.6) \
		.set_delay(0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(label, "outline_modulate:a", 0.0, 0.6) \
		.set_delay(0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
