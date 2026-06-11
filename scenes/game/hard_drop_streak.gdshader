shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Driven by tween — 0 when fully faded out.
uniform float intensity : hint_range(0.0, 2.0) = 0.8;

void fragment() {
	float y  = UV.y;              // 0 = tip (drop origin), 1 = base (landing)
	float cx = abs(UV.x - 0.5);  // 0 at centre axis, 0.5 at quad edge

	// Teardrop: half-width follows sqrt(y) so the sides curve outward instead of
	// going straight — at y=0.25 the shape is already 50% as wide as at y=1,
	// giving the characteristic bulge of a teardrop vs the straight edges of a cone.
	// dist_inside > 0 means inside the shape, < 0 means outside.
	float dist_inside = sqrt(y) * 0.5 - cx;

	// Soft outer halo — bleeds slightly beyond the cone edge.
	float glow = smoothstep(-0.10, 0.08, dist_inside);
	// Tight bright core along the centre axis.
	float core = smoothstep(0.0, 0.12, dist_inside);

	// Vertical: ramps up from the tip, peaks around y ≈ 0.85, then tapers back to zero
	// at the base — so both ends of the shape are pointed (true teardrop).
	float vert = y * y * smoothstep(1.0, 0.82, y);

	ALBEDO = vec3(1.0);
	ALPHA  = clamp(glow * 0.55 + core * 0.8, 0.0, 1.0) * vert * intensity;
}
