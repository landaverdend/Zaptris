shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// progress sweeps from -band_width to 1+band_width driven by a tween.
uniform float progress   : hint_range(-0.5, 1.5) = -0.3;
uniform float band_width : hint_range(0.0,  0.5) = 0.3;
uniform float intensity  : hint_range(0.0,  1.0) = 1.0;

void fragment() {
	// Solid white fill for everything the band has already passed.
	float fill = smoothstep(0.0, 0.02, progress - UV.x);
	// Bright leading edge — slightly wider/brighter than the fill for the glow.
	float band = smoothstep(band_width, 0.0, abs(UV.x - progress));

	ALBEDO = vec3(1.0);
	ALPHA  = clamp(fill + band, 0.0, 1.0) * intensity;
}
