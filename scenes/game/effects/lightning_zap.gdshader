shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;

uniform float progress   : hint_range(0.0, 1.0) = 0.0;
uniform float fade       : hint_range(0.0, 1.0) = 1.0;
uniform float bolt_width : hint_range(0.005, 0.15) = 0.04;
uniform vec3  bolt_color : source_color = vec3(0.55, 0.85, 1.0);

void fragment() {
	vec2 uv = UV;

	if (uv.y > progress) {
		ALPHA = 0.0;
	} else {
		float jag = sin(uv.y * 22.0 + TIME * 55.0) * 0.055
		          + sin(uv.y *  9.0 + TIME * 30.0) * 0.08;

		float dx = abs(uv.x - 0.5 - jag);

		float core = smoothstep(bolt_width,       bolt_width * 0.25, dx);
		float glow = smoothstep(bolt_width * 4.0, 0.0,               dx) * 0.35;

		float brightness = (core * 2.5 + glow) * fade;

		ALBEDO   = bolt_color;
		EMISSION = bolt_color * brightness;
		ALPHA    = clamp(core + glow, 0.0, 1.0) * fade;
	}
}
