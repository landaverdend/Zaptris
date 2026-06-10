shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

// Dark gap between cells
uniform vec3 line_color : source_color = vec3(0.012, 0.012, 0.018);
// Slightly lighter square inside each cell
uniform vec3 cell_color : source_color = vec3(0.07, 0.07, 0.10);
// Border as a fraction of one cell (0.07 = 7% each side → ~86% of block size visible)
uniform float border      : hint_range(0.0, 0.45) = 0.07;
uniform float cell_alpha  : hint_range(0.0, 1.0)  = 1.0;
uniform float line_alpha  : hint_range(0.0, 1.0)  = 0.9;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// BoxMesh is 10 x 20 x 0.2, centered at origin in local space.
	// VERTEX.x: -5 → +5, VERTEX.y: -10 → +10
	// Remap to 0..10 / 0..20 so each unit = one grid cell = one block.
	vec2 grid = vec2(local_pos.x + 5.0, local_pos.y + 10.0);
	vec2 f    = fract(grid);
	bool in_cell = f.x > border && f.x < 1.0 - border
	            && f.y > border && f.y < 1.0 - border;
	ALBEDO = in_cell ? cell_color : line_color;
	ALPHA  = in_cell ? cell_alpha  : line_alpha;
}
