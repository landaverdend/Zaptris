extends Node

## Shuffled, crossfading background-music jukebox.
## Tracks are preloaded so exported builds include the imported streams reliably.

signal track_changed(track_path: String)

const CROSSFADE_TIME := 3.0
const SILENT_DB := -80.0
const NOW_PLAYING_SCENE := preload("res://scenes/game/ui/now_playing_display.tscn")
const TRACKS := [
	{
		"path": "res://assets/audio/ambient/Double Joint_Trey Smith.mp3",
		"stream": preload("res://assets/audio/ambient/Double Joint_Trey Smith.mp3"),
	},
	{
		"path": "res://assets/audio/ambient/Kin City Disco.mp3",
		"stream": preload("res://assets/audio/ambient/Kin City Disco.mp3"),
	},
]

var _tracks: Array[Dictionary] = []
var _last_track_path: String = ""
var _players: Array[AudioStreamPlayer] = []
var _current_player: AudioStreamPlayer

func _ready() -> void:
	_tracks.assign(TRACKS)
	if _tracks.is_empty():
		push_warning("Ambience: no tracks configured")
		return

	# Owned here (not by any game mode) so it persists across scene changes
	# the same way the music itself does.
	var now_playing := NOW_PLAYING_SCENE.instantiate()
	add_child(now_playing)
	track_changed.connect(now_playing.show_track)

	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		p.finished.connect(_on_track_finished.bind(p))
		_players.append(p)

	_play_next()

# Random pick that avoids repeating the track that's currently/just playing.
func _pick_next_track() -> Dictionary:
	if _tracks.size() == 1:
		return _tracks[0]
	var candidate := _tracks[0]
	while candidate["path"] == _last_track_path:
		candidate = _tracks[randi() % _tracks.size()]
	return candidate

func _play_next() -> void:
	var track := _pick_next_track()
	_last_track_path = track["path"]
	track_changed.emit(_last_track_path)

	var outgoing := _current_player
	var incoming: AudioStreamPlayer = _players[1] if outgoing == _players[0] else _players[0]

	incoming.stream = track["stream"]
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
