shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

// Rim/fresnel glow: surfaces facing the camera read as dim and see-through;
// surfaces at a grazing angle (the edges of a beveled bar, as seen from the
// front) read as bright and opaque. Gives a "glowing glass tube" look where
// the border concentrates the glow and the flat face stays transparent.

uniform vec3  glow_color   : source_color = vec3(0.8235294, 0.3764706, 0.0);
uniform float rim_power    : hint_range(0.5, 8.0)  = 3.0;
uniform float rim_energy   : hint_range(0.0, 20.0) = 8.0;
uniform float base_energy  : hint_range(0.0, 5.0)  = 0.6;
uniform float center_alpha : hint_range(0.0, 1.0)  = 0.3;
uniform float edge_alpha   : hint_range(0.0, 1.0)  = 0.95;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	// 0 = facing the camera straight-on, 1 = grazing/edge-on.
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), rim_power);

	ALBEDO   = glow_color;
	EMISSION = glow_color * (base_energy + rim * rim_energy);
	ALPHA    = mix(center_alpha, edge_alpha, rim);
}
