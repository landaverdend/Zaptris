shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// How bright the effect is at its peak (bottom of drop).
uniform float intensity : hint_range(0.0, 1.0) = 0.12;
// UV.y value above which alpha is zero — computed from drop height so
// the fade always covers exactly FADE_ROWS cells regardless of drop distance.
uniform float fade_fraction : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// UV.y = 0 at top of quad (drop start), 1 at bottom (landing point).
	// smoothstep returns 0 below fade_fraction and ramps to 1 at UV.y = 1.
	float vertical = smoothstep(fade_fraction, 1.0, UV.y);
	ALBEDO = vec3(1.0);
	ALPHA  = vertical * intensity;
}
