// Emissive halo shell (specs/001-quest3-saber-perf FR-046).
//
// Drawn as a slightly enlarged copy of the real mesh, sharing the same Mesh resource so
// it follows the Show/Hide animations for free. $box_edges picks the mask:
//   * false -> capsule blades: a grazing-angle rim, i.e. the classic tube glow.
//   * true  -> note cubes: flat faces never graze the eye, so the fresnel term would be
//              invisible on them; the mask is instead "within 20% of a face edge",
//              measured from the local position against the mesh AABB (see half_extent).
//
// Additive, no depth write, no shadows: it adds light to what is already there and can
// never occlude anything, which is also why it is stereo-safe (NORMAL/VIEW are per eye).
// It is a MeshInstance3D only: no Area3D, no collision, no script, so neither the physics
// server nor the HitResolver can ever see it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;

uniform vec3 color : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float rim_power = 1.5;
uniform bool box_edges = false;
uniform vec3 half_extent = vec3(0.5);

varying vec3 local_pos;
varying vec3 local_n;

void vertex() {
	local_pos = VERTEX;
	// NORMAL is view space in the fragment stage; the edge mask compares it against a
	// model-space position, so the model-space normal has to be captured here.
	local_n = NORMAL;
}

void fragment() {
	float mask;
	if (box_edges) {
		vec3 a = abs(local_pos) / max(half_extent, vec3(1e-4));
		// The two axes that vary across the face we are looking at: the third one is
		// pinned at +/-1 by the face itself and would otherwise mask everything out.
		vec3 axis_mask = 1.0 - step(vec3(0.5), abs(normalize(local_n)));
		float m = max(a.x * axis_mask.x, max(a.y * axis_mask.y, a.z * axis_mask.z));
		mask = smoothstep(0.80, 1.0, m);
	} else {
		// Brightest where the shell faces the eye and fading to zero at the edge: the
		// inverse (1 - |N.V|) draws a hard hollow outline on a shell this wide.
		mask = pow(clamp(dot(normalize(local_n), normalize(VIEW)), 0.0, 1.0), rim_power);
	}
	ALBEDO = color * energy * mask;
}
