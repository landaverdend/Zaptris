shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3  flash_color : source_color = vec3(1.0, 0.8, 0.4);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float glow = 1.0 - smoothstep(0.0, 1.0, d);
	glow *= glow; // tighten the falloff toward the center

	ALBEDO   = flash_color;
	EMISSION = flash_color * glow * intensity * 4.0;
	ALPHA    = glow * intensity;
}
