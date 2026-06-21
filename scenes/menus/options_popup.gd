extends Control

signal closed

@onready var nwc_edit: LineEdit         = $CenterContainer/VBox/NWCRow/NWCEdit
@onready var paste_btn: Button         = $CenterContainer/VBox/NWCRow/PasteButton
@onready var check_btn: Button         = $CenterContainer/VBox/NWCRow/CheckButton
@onready var nwc_status: Label         = $CenterContainer/VBox/NWCStatus
@onready var free_mode_check: CheckButton = $CenterContainer/VBox/FreeModeRow/FreeModeCheck
@onready var buy_in_value: Label       = $CenterContainer/VBox/BuyInRow/BuyInValue
@onready var host_payout_value: Label  = $CenterContainer/VBox/HostPayoutRow/HostPayoutValue
@onready var sfx_slider: HSlider       = $CenterContainer/VBox/SFXRow/SFXSlider
@onready var bgm_slider: HSlider       = $CenterContainer/VBox/BGMRow/BGMSlider
@onready var close_btn: Button         = $CenterContainer/VBox/CloseButton
@onready var keyboard: Control         = $OnscreenKeyboard

const SATS_STEP := 5
const ENV_PATH  := "res://.env"

func _ready() -> void:
	hide()

	# If no override has been typed in yet, show whatever's actually active —
	# the .env fallback the bridge would otherwise silently fall back to —
	# rather than a misleadingly blank field. Just displaying this doesn't
	# create an override; only actually editing the field does (below).
	nwc_edit.text = Settings.nwc_string if not Settings.nwc_string.is_empty() else _read_env_nwc()
	free_mode_check.button_pressed = Settings.free_mode
	buy_in_value.text = str(Settings.buy_in_sats)
	host_payout_value.text = str(Settings.host_payout_sats)
	sfx_slider.value = Settings.sfx_volume
	bgm_slider.value = Settings.bgm_volume

	nwc_edit.text_changed.connect(Settings.set_nwc_string)
	nwc_edit.gui_input.connect(_on_nwc_gui_input)
	paste_btn.pressed.connect(_on_paste_pressed)
	check_btn.pressed.connect(_on_check_pressed)
	free_mode_check.toggled.connect(Settings.set_free_mode)
	$CenterContainer/VBox/BuyInRow/BuyInDec.pressed.connect(func(): _step_buy_in(-SATS_STEP))
	$CenterContainer/VBox/BuyInRow/BuyInInc.pressed.connect(func(): _step_buy_in(SATS_STEP))
	$CenterContainer/VBox/HostPayoutRow/HostPayoutDec.pressed.connect(func(): _step_host_payout(-SATS_STEP))
	$CenterContainer/VBox/HostPayoutRow/HostPayoutInc.pressed.connect(func(): _step_host_payout(SATS_STEP))
	sfx_slider.value_changed.connect(Settings.set_sfx_volume)
	bgm_slider.value_changed.connect(Settings.set_bgm_volume)
	close_btn.pressed.connect(close)
	keyboard.closed.connect(func(): Settings.set_nwc_string(nwc_edit.text))

func _step_buy_in(delta: int) -> void:
	Settings.set_buy_in_sats(Settings.buy_in_sats + delta)
	buy_in_value.text = str(Settings.buy_in_sats)

func _step_host_payout(delta: int) -> void:
	Settings.set_host_payout_sats(Settings.host_payout_sats + delta)
	host_payout_value.text = str(Settings.host_payout_sats)

func open() -> void:
	show()
	close_btn.grab_focus()

func close() -> void:
	hide()
	closed.emit()

# Controller path into the on-screen keyboard, same pattern as the lobby
# card's Lightning-address field — mouse/keyboard users can still click and
# type into the field directly since it stays editable.
func _on_nwc_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		keyboard.open(nwc_edit)

func _on_paste_pressed() -> void:
	nwc_edit.text = DisplayServer.clipboard_get()
	Settings.set_nwc_string(nwc_edit.text)

# Spins up a throwaway bridge just to test the string — doesn't touch any
# live connection a running match might have (there isn't one here anyway;
# this menu has no game session). Needs its own poll Timer since nothing
# else drains its event queue the way payment_service.gd normally does.
# Both freed once the result comes back.
func _on_check_pressed() -> void:
	if nwc_edit.text.is_empty():
		return
	check_btn.disabled = true
	nwc_status.text = "Checking..."
	nwc_status.modulate = Color.WHITE
	nwc_status.show()

	var bridge := RustBridge.new()
	add_child(bridge)
	var poll_timer := Timer.new()
	poll_timer.wait_time = 0.25
	poll_timer.autostart = true
	poll_timer.timeout.connect(bridge.poll)
	add_child(poll_timer)

	bridge.nwc_checked.connect(_on_nwc_checked.bind(bridge, poll_timer), CONNECT_ONE_SHOT)
	bridge.check_nwc_string(nwc_edit.text)

func _on_nwc_checked(success: bool, message: String, bridge: Node, poll_timer: Timer) -> void:
	nwc_status.text = message
	nwc_status.modulate = Color.GREEN if success else Color.RED
	check_btn.disabled = false
	poll_timer.queue_free()
	bridge.queue_free()

# Display-only fallback — reads HOST_NWC straight out of .env so the field
# isn't blank when the bridge is actually using that instead of an override.
func _read_env_nwc() -> String:
	if not FileAccess.file_exists(ENV_PATH):
		return ""
	var f := FileAccess.open(ENV_PATH, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("HOST_NWC="):
			return line.substr(len("HOST_NWC=")).strip_edges()
	return ""
