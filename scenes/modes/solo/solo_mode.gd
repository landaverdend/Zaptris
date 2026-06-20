extends Node3D

const PlayerInputScript  := preload("res://scenes/game/logic/player_input.gd")

# ── State machine ──────────────────────────────────────────────────────────────

enum State { COUNTDOWN, PLAYING, PAUSED, GAME_OVER }
var state := State.COUNTDOWN

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var logic: Node               = $GameArena/GameLogic
@onready var countdown: Control        = $UILayer/Countdown
@onready var game_over_screen: Control = $UILayer/GameOverScreen
@onready var final_score_label: Label  = $UILayer/GameOverScreen/CenterContainer/VBox/FinalScore
@onready var pause_screen: Control     = $UILayer/PauseScreen
@onready var _resume_btn: Button       = $UILayer/PauseScreen/CenterContainer/VBox/ResumeButton
@onready var _game_over_restart_btn: Button = $UILayer/GameOverScreen/CenterContainer/VBox/RestartButton

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	countdown.finished.connect(_on_countdown_finished)

	game_over_screen.hide()
	pause_screen.hide()

	logic.game_over.connect(_on_game_over)

	# Game over screen buttons
	$UILayer/GameOverScreen/CenterContainer/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UILayer/GameOverScreen/CenterContainer/VBox/MenuButton.pressed.connect(_on_menu_pressed)

	# Pause screen buttons
	$UILayer/PauseScreen/CenterContainer/VBox/ResumeButton.pressed.connect(_on_resume_pressed)
	$UILayer/PauseScreen/CenterContainer/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UILayer/PauseScreen/CenterContainer/VBox/MenuButton.pressed.connect(_on_menu_pressed)

	countdown.start()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()

# ── Transitions ───────────────────────────────────────────────────────────────


func _on_countdown_finished() -> void:
	_start_game()

func _start_game() -> void:
	state = State.PLAYING
	$GameArena/PlayerInput.configure(PlayerInputScript.InputSource.ANY)
	$GameArena/PlayerInput.clear_held()
	logic.start()
	await get_tree().create_timer(0.6).timeout
	countdown.hide()

func _pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	pause_screen.show()
	_resume_btn.grab_focus()

func _on_resume_pressed() -> void:
	_resume()

func _resume() -> void:
	state = State.PLAYING
	get_tree().paused = false
	pause_screen.hide()

func _on_game_over() -> void:
	state = State.GAME_OVER
	final_score_label.text = "SCORE\n%d" % logic.scorer.score
	game_over_screen.show()
	_game_over_restart_btn.grab_focus()

func _on_restart_pressed() -> void:
	get_tree().paused = false
	game_over_screen.hide()
	pause_screen.hide()
	logic.reset(randi())
	state = State.COUNTDOWN
	countdown.start()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
