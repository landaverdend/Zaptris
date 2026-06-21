shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

// Inverted-hull outline: vertices are pushed outward along their normals so
// only the silhouette peeks out from behind the glow mesh, reading as a
// dark contour that keeps the glow legible against any background.

uniform float outline_width : hint_range(0.0, 0.5) = 0.05;
uniform vec3 outline_color : source_color = vec3(0.02, 0.03, 0.05);
// For meshes with many small bevel facets, extruding along each vertex's own
// normal produces an uneven, scalloped silhouette. Scaling outward from the
// mesh's local origin instead avoids that entirely, but only looks even when
// the mesh is roughly centered on its own origin (true for the small box
// frames, not for the asymmetric board frame).
uniform bool use_scale_extrude = false;

void vertex() {
	if (use_scale_extrude) {
		VERTEX *= 1.0 + outline_width;
	} else {
		VERTEX += NORMAL * outline_width;
	}
}

void fragment() {
	ALBEDO = outline_color;
}
