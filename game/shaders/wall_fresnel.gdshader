// Fresnel wall material (specs/007-visual-options FR-009).
//
// Only ever assigned when Settings.wall_fresnel is on (default off): it adds overdraw on
// purpose, so it waits for a measurement like every other addition in this sheet.
//
// Additive and unshaded. Additive was chosen over a mix/alpha variant because it needs no
// sorting of the transparent queue: draw order cannot change the result, which is the
// cheapest thing an overdraw-heavy wall can be on a mobile tiler. The cost is that the wall
// reads as light rather than as a panel, so the edge band below is much brighter than the
// fresnel term - the outline is what tells the eye where the wall actually is.
//
// The near fade is the rule that makes an additive wall safe: a wall the player is standing
// inside would otherwise fill the whole field with additive fill. `VERTEX` is in view space
// in the fragment shader, so its length is the distance to the eye and the fade needs no
// extra uniform or camera transform.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// The wall's size in metres. An INSTANCE uniform, not a material parameter: one shared
// material serves every wall, and a plain uniform would resize them all at once (Wall.gd
// writes this per spawn).
instance uniform vec3 size = vec3(1.0);

uniform vec4 wall_color : source_color = vec4(0.85, 0.30, 0.95, 1.0);
// Base fill inside the wall faces. Kept low: the fresnel and the frame carry the look, and
// a bright even fill over a large quad is exactly the overdraw this setting has to justify.
uniform float fill_energy = 0.05;
uniform float fresnel_energy = 0.55;
uniform float fresnel_power = 2.5;
uniform float frame_energy = 0.9;
// Half-width of the bright border band, in metres.
uniform float frame_width = 0.07;
// Distance (metres) over which a wall fades out as the camera approaches it (FR-009).
uniform float near_fade = 0.6;

varying vec3 local;

void vertex() {
	// BoxMesh in its own space, so the frame band is measured against the wall's real size.
	local = VERTEX;
}

void fragment() {
	// 1 at the silhouette, 0 face on. NORMAL and VIEW are both view space.
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0),
		fresnel_power);
	// Distance from the nearest edge of the face, in metres.
	vec3 half_size = max(size * 0.5, vec3(1e-4));
	float edge = min(half_size.x - abs(local.x), half_size.y - abs(local.y));
	// smoothstep keeps the band anti-aliased: a hard step would alias badly at distance,
	// where the whole wall is a few pixels wide.
	float frame = 1.0 - smoothstep(0.0, frame_width, edge);
	// Fade to zero at the eye and reach full strength by near_fade.
	float near = smoothstep(0.0, near_fade, length(VERTEX));
	float energy = (fill_energy + fresnel * fresnel_energy + frame * frame_energy) * near;
	ALBEDO = wall_color.rgb * energy;
}
