# Controller binding profiles.
# Each action maps to an Array of JoyButton values so multiple buttons can
# trigger the same action (e.g. A or Y for rotate right in Tetris 99).
#
# Add new profiles by duplicating an existing _*_profile() function and
# registering it in get_bindings() / friendly_name() below.
#
# ── Godot vs Switch label mismatch ────────────────────────────────────────────
# Godot maps buttons by physical position, not printed label:
#   Switch A (east)  → JOY_BUTTON_B
#   Switch B (south) → JOY_BUTTON_A
#   Switch X (north) → JOY_BUTTON_Y
#   Switch Y (west)  → JOY_BUTTON_X
# ─────────────────────────────────────────────────────────────────────────────

# Default DAS/ARR for controllers — Tetris 99 inspired.
# DAS: ~9 frames (150ms). ARR: 0 = instant (pieces snap to wall after DAS).
const DEFAULT_CONTROLLER_DAS := 12.0
const DEFAULT_CONTROLLER_ARR := 2.0

static func get_bindings(joy_name: String) -> Dictionary:
	if _is_switch(joy_name):
		return _switch_profile()
	return _switch_profile()  # safe default until more profiles are added

static func friendly_name(joy_name: String) -> String:
	if _is_switch(joy_name):
		return "Switch Controller"
	return joy_name

# ── Detection helpers ─────────────────────────────────────────────────────────

static func _is_switch(joy_name: String) -> bool:
	var lower := joy_name.to_lower()
	return "switch" in lower or "joy-con" in lower or "pro controller" in lower

# ── Profiles ──────────────────────────────────────────────────────────────────

# Tetris 99 Switch layout.
# Rotate right: A or Y  |  Rotate left: B or X  |  Hold: L or R
static func _switch_profile() -> Dictionary:
	return {
		"move_left":  [JOY_BUTTON_DPAD_LEFT],
		"move_right": [JOY_BUTTON_DPAD_RIGHT],
		"soft_drop":  [JOY_BUTTON_DPAD_DOWN],
		"hard_drop":  [JOY_BUTTON_DPAD_UP],
		"rotate_cw":  [JOY_BUTTON_B, JOY_BUTTON_X],              # A or Y on Switch
		"rotate_ccw": [JOY_BUTTON_A, JOY_BUTTON_Y],              # B or X on Switch
		"hold":       [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER],
	}
