extends Node

## Shuffled, crossfading background-music jukebox.
## Drop any .mp3/.ogg files into AMBIENT_DIR and they're picked up automatically
## at startup — no per-track wiring needed.

const AMBIENT_DIR := "res://assets/audio/ambient/"
const CROSSFADE_TIME := 3.0
const SILENT_DB := -80.0

var _tracks: Array[String] = []
var _last_track: String = ""
var _players: Array[AudioStreamPlayer] = []
var _current_player: AudioStreamPlayer

func _ready() -> void:
	_tracks = _scan_tracks()
	if _tracks.is_empty():
		push_warning("Ambience: no tracks found in %s" % AMBIENT_DIR)
		return

	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		p.finished.connect(_on_track_finished.bind(p))
		_players.append(p)

	_play_next()

func _scan_tracks() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(AMBIENT_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".mp3") or file_name.ends_with(".ogg")):
			found.append(AMBIENT_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return found

# Random pick that avoids repeating the track that's currently/just playing.
func _pick_next_track() -> String:
	if _tracks.size() == 1:
		return _tracks[0]
	var candidate := _last_track
	while candidate == _last_track:
		candidate = _tracks[randi() % _tracks.size()]
	return candidate

func _play_next() -> void:
	var track := _pick_next_track()
	_last_track = track

	var outgoing := _current_player
	var incoming: AudioStreamPlayer = _players[1] if outgoing == _players[0] else _players[0]

	incoming.stream = load(track)
	incoming.volume_db = SILENT_DB
	incoming.play()
	_current_player = incoming

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, CROSSFADE_TIME)
	if outgoing != null and outgoing.playing:
		tw.tween_property(outgoing, "volume_db", SILENT_DB, CROSSFADE_TIME)
		tw.chain().tween_callback(outgoing.stop)

# Only the player that's actually carrying the active track should advance
# the playlist — the outgoing player's stream also ends mid-fade-out, but it's
# already been silenced/stopped by the crossfade tween above.
func _on_track_finished(player: AudioStreamPlayer) -> void:
	if player == _current_player:
		_play_next()
