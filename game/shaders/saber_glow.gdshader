// Camera-facing saber glow strip (specs/007-visual-options, 007 rule 3).
//
// Replaces the 2.4x additive capsule shell. The shell was a tube: the eye saw its front
// half, and the half wrapped around the sides only ever contributed overdraw, so most of
// its volume was never visible. This is one quad, billboarded about the blade axis in the
// vertex shader, so it always presents its full width to the eye and costs one layer of
// fragments instead of a tube's worth.
//
// The width is 1.5x the blade's diameter and the falloff is steeper than the old rim, which
// is what keeps the smaller geometry reading as the same glow. Sampling the height from the
// node's own mesh means the Show/Hide animation shortens the strip for free.
//
// The colour is the LIGHT colour (`light_left`/`light_right`, already tinted once at the
// source), so a map light event that turns the level red tints the glow as well without
// this shader multiplying any tint of its own (007 rule 6). Additive, no depth write, no
// shadows: it can only add light and can never occlude anything, which also makes it
// stereo-safe (the billboard axis is per eye).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;

global uniform vec3 light_left;
global uniform vec3 light_right;

// 0 = left blade, 1 = right blade. One write per saber, never per frame.
uniform int side = 0;
uniform float energy = 0.45;
// Half width in metres at thickness 1.0: 1.5x the 0.024 m blade diameter, halved.
uniform float half_width = 0.018;
// Higher than the old 1.5 rim power: the strip is narrower, so the edge has to fall away
// faster to keep the same apparent size.
uniform float falloff = 2.5;
// Fraction of the blade length faded out at each end, so the strip has no hard cut.
uniform float cap_fade = 0.06;
// Hard ceiling for this additive layer (007 rule 6).
uniform float peak = 1.1;

varying vec2 quad_uv;

void vertex() {
	// QuadMesh UVs: 0..1 across and 0..1 along, independent of the animated size.
	quad_uv = UV;
	// The blade axis and the point on it this vertex belongs to, both in view space.
	vec3 axis_view = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 centre_view = (MODELVIEW_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0)).xyz;
	// Lateral direction: perpendicular to the blade and to the eye ray. The eye is at the
	// origin of view space, looking down -Z.
	vec3 to_cam = -normalize(centre_view);
	vec3 lateral = cross(axis_view, to_cam);
	float lateral_len = length(lateral);
	// Blade pointing straight at the eye: no meaningful side vector, so collapse to a
	// degenerate strip rather than producing NaNs.
	lateral = lateral_len > 1e-5 ? lateral / lateral_len : vec3(0.0);
	// MODELVIEW_MATRIX's x axis length carries the saber thickness scale, so the strip widens with
	// the blade as set_thickness() changes it.
	float thickness = length((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	float w = half_width * max(thickness, 1e-3);
	vec3 view_pos = centre_view + lateral * (sign(VERTEX.x) * w);
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	float lat = abs(quad_uv.x * 2.0 - 1.0);
	float along = abs(quad_uv.y * 2.0 - 1.0);
	// Brightness falls off with distance from the blade line.
	float mask = pow(clamp(1.0 - lat, 0.0, 1.0), falloff);
	mask *= 1.0 - smoothstep(1.0 - cap_fade, 1.0, along);
	vec3 light = side > 0 ? light_right : light_left;
	ALBEDO = min(light * energy * mask, vec3(peak));
}

