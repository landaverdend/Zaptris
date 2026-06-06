extends Control


func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/solo/solo_mode.tscn")

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/modes/local/local_mode.tscn")
