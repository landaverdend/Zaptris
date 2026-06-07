shader_type sky;

void sky() {
	// EYEDIR.y: 1 = straight up, 0 = horizon, -1 = below
	float h = EYEDIR.y;

	vec3 top     = vec3(0.01, 0.01, 0.04);  // near-black
	vec3 mid     = vec3(0.04, 0.02, 0.14);  // deep purple
	vec3 horizon = vec3(0.28, 0.04, 0.08);  // dark red glow

	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.25, h));
	col      = mix(col,     top, smoothstep(0.15, 1.0,  h));

	COLOR = col;
}
