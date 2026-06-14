extends Control

@onready var _solo_btn: Button = $CenterContainer/VBoxContainer/Solo

func _ready() -> void:
	_solo_btn.grab_focus()

func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/solo/solo_mode.tscn")

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/local/local_mode.tscn")
