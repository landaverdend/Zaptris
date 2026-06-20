extends Node

## One-shot sound effects, keyed by name. Add a new sound by adding one
## entry here and one logic.<signal>.connect(sfx.play.bind("name")) line in
## game_arena.gd — no new nodes or scene edits required.
## volume_db here is *relative balance between sounds*, not overall loudness
## — overall SFX loudness is the "SFX" audio bus's volume (one knob, see
## default_bus_layout.tres), which every player below routes through.
const SOUNDS: Dictionary = {
	"rotate":    { "stream": preload("res://assets/audio/effects/rotation.wav"),  "volume_db": 0.0 },
	"move":      { "stream": preload("res://assets/audio/effects/rotation.wav"),  "volume_db": 0.0 },
	"hard_drop": { "stream": preload("res://assets/audio/effects/hard_drop.wav"), "volume_db": 0.0 },
	"line_clear": { "stream": preload("res://assets/audio/effects/line_clear.wav"), "volume_db": 2.0 },
}

# How many overlapping one-shots can play at once before they start cutting
# each other off — rotate/move can fire in quick succession (held DAS, 4
# simultaneous local players), so a small round-robin pool avoids cutoffs.
const POOL_SIZE := 6

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)

func play(sound_name: StringName) -> void:
	var info: Dictionary = SOUNDS.get(sound_name, {})
	if info.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = info.stream
	p.volume_db = info.get("volume_db", 0.0)
	p.play()
