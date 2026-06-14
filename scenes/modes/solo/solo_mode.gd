extends Node3D

const PlayerInputScript  := preload("res://scenes/game/logic/player_input.gd")
const CountdownScript    := preload("res://scenes/game/logic/countdown_timer.gd")

# ── State machine ──────────────────────────────────────────────────────────────

enum State { COUNTDOWN, PLAYING, PAUSED, GAME_OVER }
var state := State.COUNTDOWN

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var logic: Node               = $GameArena/GameLogic
@onready var countdown_node: Control   = $UILayer/Countdown
@onready var countdown_label: Label    = $UILayer/Countdown/Label
@onready var game_over_screen: Control = $UILayer/GameOverScreen
@onready var final_score_label: Label  = $UILayer/GameOverScreen/CenterContainer/VBox/FinalScore
@onready var pause_screen: Control     = $UILayer/PauseScreen

var countdown_timer: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	countdown_timer = CountdownScript.new()
	countdown_timer.name = "CountdownTimer"
	add_child(countdown_timer)
	countdown_timer.finished.connect(_on_countdown_finished)

	game_over_screen.hide()
	pause_screen.hide()
	countdown_node.show()

	logic.game_over.connect(_on_game_over)

	# Game over screen buttons
	$UILayer/GameOverScreen/CenterContainer/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UILayer/GameOverScreen/CenterContainer/VBox/MenuButton.pressed.connect(_on_menu_pressed)

	# Pause screen buttons
	$UILayer/PauseScreen/CenterContainer/VBox/ResumeButton.pressed.connect(_on_resume_pressed)
	$UILayer/PauseScreen/CenterContainer/VBox/RestartButton.pressed.connect(_on_restart_pressed)
	$UILayer/PauseScreen/CenterContainer/VBox/MenuButton.pressed.connect(_on_menu_pressed)

	countdown_timer.start(countdown_label)

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
	$GameArena/PlayerInput.configure(PlayerInputScript.InputSource.KEYBOARD)
	$GameArena/PlayerInput.clear_held()
	logic.start()
	await get_tree().create_timer(0.6).timeout
	countdown_node.hide()

func _pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	pause_screen.show()

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

func _on_restart_pressed() -> void:
	get_tree().paused = false
	game_over_screen.hide()
	pause_screen.hide()
	logic.reset(randi())
	state = State.COUNTDOWN
	countdown_node.show()
	countdown_timer.start(countdown_label)

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
