// Mirrored copy material (specs/001-quest3-saber-perf FR-047).
//
// The mirrored copies are drawn with a negative-determinant transform (y flipped about
// the floor). Godot flips the winding for those, so ordinary cull_back is enough; the
// colour is pre-dimmed here and the translucent floor above does the rest.
//
// Opaque and unshaded on purpose: an opaque copy needs no transparent sorting, cannot
// z-fight the floor (it is entirely below it) and costs one plain draw.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float dim : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	ALBEDO = color * dim;
}
