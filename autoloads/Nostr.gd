extends Node

# Emitted when a zap is received for a listening player.
# amount_sats: the zap amount in satoshis
signal zap_received(player_index: int, amount_sats: int)

var _bridge: RustBridge = null

func start_listening(lightning_address: String) -> void:
	if _bridge == null:
		_bridge = RustBridge.new()
		add_child(_bridge)
	_bridge.start_listening(lightning_address)

func stop_listening() -> void:
	if _bridge != null:
		_bridge.stop_listening()
		_bridge.queue_free()
		_bridge = null
