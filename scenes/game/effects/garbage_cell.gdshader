shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_prepass_alpha;

uniform float danger      : hint_range(0.0, 1.0) = 1.0;
uniform float fill_ratio  : hint_range(0.0, 1.0) = 0.0;
uniform vec3  color_a     : source_color = vec3(1.0, 0.45, 0.02);
uniform vec3  color_b     : source_color = vec3(1.0, 0.04, 0.02);
void fragment() {
	// CRT scanlines
	float scanline = 1.0 - 0.28 * step(0.5, fract(FRAGCOORD.y / 2.5));

	// Vignette per-cell
	vec2 uv = UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(uv, uv) * 0.55;
	vignette = clamp(vignette, 0.0, 1.0);

	// color_a → color_b as fill_ratio approaches 1.0 (orange → red by default)
	vec3 color = mix(color_a, color_b, fill_ratio);

	float alpha = scanline * vignette * danger;

	ALBEDO   = color;
	EMISSION = color * 2.5 * vignette;
	ALPHA    = alpha * 0.88;
}
