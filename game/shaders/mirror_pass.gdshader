// Mirrored copy drawn as a `next_pass` (specs/007-visual-options, 007 rule 2).
//
// The copy is the SAME geometry, flipped about the world y = 0 plane in the vertex shader,
// so there is no second node, no second transform to sync and no GDScript at all: the pass
// follows the object it mirrors for free. Attached to the note core and the saber blade
// only - no halos, no trail.
//
// Additive and transparent on purpose. Godot sorts each pass by that pass's own material,
// so this one lands in the transparent list and is drawn after the opaque floor pad; the
// pad itself therefore never has to leave the opaque queue. Depth test stays on so a wall
// in front of the pad still hides a reflection; depth write is off because the copy is an
// overlay, not a surface.
//
// Only the part of the copy that the pad actually reflects is kept: the fragment works out
// where the eye ray through it meets y = 0 and discards anything outside the pad. That is
// the clipping the old translucent floor did with alpha, and it costs one divide.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// The pad (see floor.tscn): PlaneMesh 0.5 scaled 4, so 2 m across, centred on the origin.
uniform vec2 pad_half = vec2(1.0, 1.0);
// Fraction of pad_half where the copy starts fading out, so the clip is not a hard edge.
uniform float pad_feather = 0.8;
uniform float dim = 0.22;
// Per instance, because the note material and the blade material are shared: this is the
// only per-object value the pass needs, and it never creates a material per object.
instance uniform vec4 mirror_color : source_color = vec4(1.0);

varying vec3 mirror_world;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	wp.y = -wp.y;
	mirror_world = wp.xyz;
	// Written directly: the flipped point is not the mesh's own transform, so the usual
	// MODELVIEW path would put it back where it came from.
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * wp;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float denom = cam.y - mirror_world.y;
	// Eye at or under the floor plane: nothing can be reflected.
	if (denom <= 1e-4) {
		discard;
	}
	float t = cam.y / denom;
	vec2 hit = cam.xz + t * (mirror_world.xz - cam.xz);
	vec2 a = abs(hit) / pad_half;
	float edge = max(a.x, a.y);
	if (edge > 1.0) {
		discard;
	}
	float fade = 1.0 - smoothstep(pad_feather, 1.0, edge);
	ALBEDO = mirror_color.rgb * dim * fade;
}
