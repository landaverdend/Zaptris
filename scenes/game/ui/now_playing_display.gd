extends CanvasLayer

## Transient "now playing" toast — fades in, holds, fades out whenever
## Ambience starts a new track. Lives on its own high-numbered CanvasLayer
## so it draws above every game mode's own UI regardless of which scene is
## currently active (Ambience instances this as its own child, so it
## persists across scene changes the same way the music itself does).

@export var fade_in_time: float = 0.4
@export var hold_time: float = 3.0
@export var fade_out_time: float = 0.8

@onready var _header: Label = $Header
@onready var _title: Label  = $Title

var _tween: Tween

func _ready() -> void:
	_header.modulate.a = 0.0
	_title.modulate.a = 0.0

func show_track(track_path: String) -> void:
	_title.text = _display_name(track_path)

	if _tween:
		_tween.kill()

	_header.modulate.a = 0.0
	_title.modulate.a = 0.0

	var fade_out_delay := fade_in_time + hold_time

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_header, "modulate:a", 1.0, fade_in_time)
	_tween.tween_property(_title, "modulate:a", 1.0, fade_in_time)
	_tween.tween_property(_header, "modulate:a", 0.0, fade_out_time).set_delay(fade_out_delay)
	_tween.tween_property(_title, "modulate:a", 0.0, fade_out_time).set_delay(fade_out_delay)

## Filenames follow "Song Name_Artist.mp3" -> rendered as "Song Name - Artist".
## No casing/spacing changes here — the filename's casing is taken as-is,
## since that's how the artist/title naming is actually meant to look.
static func _display_name(path: String) -> String:
	var base := path.get_file().get_basename()
	var parts := base.split("_", true, 1)
	if parts.size() == 2:
		return "%s - %s" % [parts[0], parts[1]]
	return base
