extends Control

const MAX_PLAYERS = 4

var player_count = 0

func _on_add_player_pressed() -> void:
	if player_count >= MAX_PLAYERS:
		return
	player_count += 1
	_add_player_slot(player_count)

func _add_player_slot(index: int) -> void:
	var slot = PanelContainer.new()
	var label = Label.new()
	label.text = "Player %d" % index
	slot.add_child(label)
	$PlayerSlots.add_child(slot)

func _on_back_pressed() -> void:
	Nostr.stop_listening()
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")

func _ready() -> void:
	Nostr.start_listening("jb55@jb55.com")
	
	
	
