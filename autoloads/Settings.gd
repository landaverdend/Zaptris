extends Node

## Game settings, edited via the Options popup. free_mode/volumes persist
## across sessions via a ConfigFile in user://. nwc_string deliberately does
## NOT persist — it's a wallet connection secret, and writing it to a plain
## settings file on disk (especially on a shared/demo machine) trades
## convenience for a real credential-exposure risk. Re-enter it each session.

signal free_mode_changed(enabled: bool)
signal sfx_volume_changed(linear: float)
signal bgm_volume_changed(linear: float)
signal buy_in_sats_changed(amount: int)
signal host_payout_sats_changed(amount: int)

const SFX_BUS   := "SFX"
const MUSIC_BUS := "Music"
const SAVE_PATH := "user://settings.cfg"

## NWC connection string. If set, payment_service.gd passes this to
## RustBridge.set_nwc_override() before it enters the tree, which takes
## priority over HOST_NWC from .env. Empty means "use .env as before".
## Not persisted — see note above.
var nwc_string: String = ""

var free_mode: bool = true

## Per-player buy-in, charged when free_mode is OFF.
var buy_in_sats: int = 25
## Starting pot size, funded by the host, when free_mode is ON.
var host_payout_sats: int = 100

var sfx_volume: float = 1.0  # linear 0..1
var bgm_volume: float = 1.0  # linear 0..1

# The bus layout's own baseline dB (e.g. Music is mixed a bit quieter by
# default) — sliders scale relative to that instead of overwriting it.
var _sfx_baseline_db: float = 0.0
var _bgm_baseline_db: float = 0.0

func _ready() -> void:
	var sfx_idx := AudioServer.get_bus_index(SFX_BUS)
	if sfx_idx >= 0:
		_sfx_baseline_db = AudioServer.get_bus_volume_db(sfx_idx)
	var bgm_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bgm_idx >= 0:
		_bgm_baseline_db = AudioServer.get_bus_volume_db(bgm_idx)
	_load()
	_apply_sfx_volume()
	_apply_bgm_volume()

func set_nwc_string(value: String) -> void:
	nwc_string = value

func set_free_mode(enabled: bool) -> void:
	free_mode = enabled
	free_mode_changed.emit(enabled)
	_save()

func set_buy_in_sats(amount: int) -> void:
	buy_in_sats = maxi(1, amount)
	buy_in_sats_changed.emit(buy_in_sats)
	_save()

func set_host_payout_sats(amount: int) -> void:
	host_payout_sats = maxi(1, amount)
	host_payout_sats_changed.emit(host_payout_sats)
	_save()

func set_sfx_volume(linear: float) -> void:
	sfx_volume = clampf(linear, 0.0, 1.0)
	_apply_sfx_volume()
	sfx_volume_changed.emit(sfx_volume)
	_save()

func set_bgm_volume(linear: float) -> void:
	bgm_volume = clampf(linear, 0.0, 1.0)
	_apply_bgm_volume()
	bgm_volume_changed.emit(bgm_volume)
	_save()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("match", "free_mode", free_mode)
	cfg.set_value("match", "buy_in_sats", buy_in_sats)
	cfg.set_value("match", "host_payout_sats", host_payout_sats)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no saved file yet — keep the hardcoded defaults above
	sfx_volume       = cfg.get_value("audio", "sfx_volume", sfx_volume)
	bgm_volume       = cfg.get_value("audio", "bgm_volume", bgm_volume)
	free_mode        = cfg.get_value("match", "free_mode", free_mode)
	buy_in_sats      = cfg.get_value("match", "buy_in_sats", buy_in_sats)
	host_payout_sats = cfg.get_value("match", "host_payout_sats", host_payout_sats)

func _apply_sfx_volume() -> void:
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _sfx_baseline_db + linear_to_db(sfx_volume))

func _apply_bgm_volume() -> void:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _bgm_baseline_db + linear_to_db(bgm_volume))
