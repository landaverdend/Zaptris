extends Control

signal closed

@onready var nwc_edit: LineEdit         = $CenterContainer/VBox/NWCRow/NWCEdit
@onready var paste_btn: Button         = $CenterContainer/VBox/NWCRow/PasteButton
@onready var free_mode_check: CheckButton = $CenterContainer/VBox/FreeModeRow/FreeModeCheck
@onready var buy_in_value: Label       = $CenterContainer/VBox/BuyInRow/BuyInValue
@onready var host_payout_value: Label  = $CenterContainer/VBox/HostPayoutRow/HostPayoutValue
@onready var sfx_slider: HSlider       = $CenterContainer/VBox/SFXRow/SFXSlider
@onready var bgm_slider: HSlider       = $CenterContainer/VBox/BGMRow/BGMSlider
@onready var close_btn: Button         = $CenterContainer/VBox/CloseButton
@onready var keyboard: Control         = $OnscreenKeyboard

const SATS_STEP := 5

func _ready() -> void:
	hide()

	nwc_edit.text = Settings.nwc_string
	free_mode_check.button_pressed = Settings.free_mode
	buy_in_value.text = str(Settings.buy_in_sats)
	host_payout_value.text = str(Settings.host_payout_sats)
	sfx_slider.value = Settings.sfx_volume
	bgm_slider.value = Settings.bgm_volume

	nwc_edit.text_changed.connect(Settings.set_nwc_string)
	nwc_edit.gui_input.connect(_on_nwc_gui_input)
	paste_btn.pressed.connect(_on_paste_pressed)
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
