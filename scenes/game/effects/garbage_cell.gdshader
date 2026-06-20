shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_prepass_alpha;

uniform float danger      : hint_range(0.0, 1.0) = 1.0;
uniform float fill_ratio  : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	// CRT scanlines
	float scanline = 1.0 - 0.28 * step(0.5, fract(FRAGCOORD.y / 2.5));

	// Vignette per-cell
	vec2 uv = UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(uv, uv) * 0.55;
	vignette = clamp(vignette, 0.0, 1.0);

	// Orange → red as fill_ratio approaches 1.0
	vec3 orange = vec3(1.0, 0.45, 0.02);
	vec3 red    = vec3(1.0, 0.04, 0.02);
	vec3 color  = mix(orange, red, fill_ratio);

	float alpha = scanline * vignette * danger;

	ALBEDO   = color;
	EMISSION = color * 2.5 * vignette;
	ALPHA    = alpha * 0.88;
}
