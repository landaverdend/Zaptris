shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;

uniform float danger : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Distance from nearest edge (0.0 = at the edge, 0.5 = dead centre)
	float dx = min(UV.x, 1.0 - UV.x);
	// Top edge gets a shorter gradient — that's where the stack fills from
	float dy = min(UV.y * 2.5, 1.0 - UV.y);
	float edge_dist = min(dx, dy);

	float border = 1.0 - smoothstep(0.0, 0.14, edge_dist);
	float pulse  = 0.08 + 0.07 * sin(TIME * 2.5);

	ALBEDO = vec3(1.0, 0.04, 0.04);
	ALPHA  = border * pulse * danger;
}
