extends Node3D

## Stretches and orients the existing LightningZap bolt so it visually
## connects two arbitrary world points (pot → a player's SatsBox), instead
## of lightning_zap's normal fixed "strike straight down" use. SatsBox
## position varies with player count/layout, so this is computed live from
## play_between()'s arguments rather than any fixed coordinate.

const LIGHTNING_ZAP_SCENE := preload("res://scenes/game/effects/lightning_zap.tscn")
## Same gold used for the pot's own zaps (local_mode.tscn) — keeps the
## "sats" visual language consistent across effects.
const ZAP_COLOR := Color(0.972549, 0.7921569, 0.0, 1.0)
## LightningZap's bolt + spark sequence runs ~0.73s end to end — free
## shortly after so it's never visibly cut off.
const ZAP_LIFETIME := 0.85

func play_between(from: Vector3, to: Vector3) -> void:
	var zap := LIGHTNING_ZAP_SCENE.instantiate()
	zap.bolt_color  = ZAP_COLOR
	zap.bolt_height = from.distance_to(to)
	add_child(zap)

	# lightning_zap's shader reveals from the bolt's far end (local +Y) down
	# toward the node's own origin (its "impact" point). Put the node at the
	# destination with +Y pointing back toward the pot, so the existing
	# strike-reveal animation reads as the bolt arriving FROM the pot
	# rather than falling from the sky.
	var y_axis := (from - to).normalized()
	var z_ref  := Vector3(0, 0, 1)  # camera is fixed and looks down -Z
	var x_axis := y_axis.cross(z_ref)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3(1, 0, 0)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), to)

	zap.play()
	await get_tree().create_timer(ZAP_LIFETIME).timeout
	queue_free()
