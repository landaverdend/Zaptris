shader_type sky;

// ── Sky gradient ───────────────────────────────────────────────────────────────
uniform vec3 sky_top     : source_color = vec3(0.00, 0.00, 0.03);
uniform vec3 sky_mid     : source_color = vec3(0.00, 0.01, 0.05);
uniform vec3 sky_horizon : source_color = vec3(0.01, 0.02, 0.08);

// ── Stars ──────────────────────────────────────────────────────────────────────
uniform float star_density   : hint_range(0.0, 0.3)   = 0.06;   // fraction of cells that get a star
uniform float star_scale     : hint_range(50.0, 500.0) = 200.0;  // higher = more stars, smaller
uniform float star_intensity : hint_range(0.0, 3.0)    = 1.4;    // overall brightness

float hash2(vec2 p) {
	p  = fract(p * vec2(127.1, 311.7));
	p += dot(p, p.yx + 19.19);
	return fract(p.x * p.y);
}

float star_field(vec3 dir) {
	const float PI = 3.14159265;

	// Equirectangular projection: sphere direction → 2D tiling coords.
	float phi   = atan(dir.z, dir.x) * (0.5 / PI) + 0.5;
	float theta = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	vec2 uv     = vec2(phi, theta) * star_scale;

	vec2  cell  = floor(uv);
	vec2  fuv   = fract(uv);
	float result = 0.0;

	// 3×3 neighbour search so stars near cell edges aren't clipped.
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2  nb = vec2(float(i), float(j));
			float h  = hash2(cell + nb);
			if (h > star_density) continue;

			// Each star gets a unique size, brightness, and position within its cell.
			float sz    = 0.003 + fract(h * 97.31)  * 0.009;
			float br    = 0.35  + fract(h * 61.93)  * 0.65;
			vec2  spos  = vec2(fract(h * 43.71), fract(h * 211.33));
			float dist  = length(nb + spos - fuv);

			// Sharp core + soft halo.
			result += smoothstep(sz, 0.0, dist) * br;
			result += smoothstep(sz * 6.0, sz * 0.5, dist) * br * 0.10;
		}
	}
	return result;
}

void sky() {
	vec3  dir = normalize(EYEDIR);
	float y   = dir.y;  // 1 = zenith, 0 = horizon, −1 = nadir

	// Three-stop gradient: zenith → mid → horizon.
	vec3 color = mix(sky_horizon, sky_mid, smoothstep(0.0, 0.3, y));
	color      = mix(color,      sky_top, smoothstep(0.2, 1.0, y));

	// Stars: fade in just above the horizon so they don't bleed into any ground plane.
	float star_fade = smoothstep(-0.06, 0.14, y);
	color += star_field(dir) * star_intensity * star_fade;

	COLOR = color;
}
