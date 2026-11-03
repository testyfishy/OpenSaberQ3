// Analytic saber light on the floor (specs/001-quest3-saber-perf FR-045,
// specs/007-visual-options FR-003/FR-005/FR-006).
//
// The floor already carries the burn trail from a SubViewport; this shader keeps that
// texture and adds a closed-form "light pool" under each blade. There is no second
// viewport, no shadow map and no scene query: the only inputs are the four world-space
// points the sabers publish once per physics tick (see project.godot [shader_globals]
// and LightSaber._physics_process).
//
// Opaque on purpose. The mirrored copies (007 rule 2) used to need a translucent floor,
// which put this whole large surface in the transparent pass: no depth prepass, no early-z
// for everything behind it. The copies are now a `next_pass` that is open only where the
// view ray meets this pad, so the pad can stay in the opaque queue. `depth_draw_never` is
// what lets that pass reach the depth buffer: it is the only thing the pad could occlude,
// and a below-floor copy is always farther from the eye than the pad itself.
//
// Stereo: world_pos comes from MODEL_MATRIX, which carries no eye offset, so both eyes
// sample the same world point on the plane and the streak stays glued to the floor. An
// eye-dependent quantity here would make the light swim between the eyes.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;

// Both blades, base and tip, in world space (tip = the existing left_saber/right_saber).
global uniform vec3 left_saber;
global uniform vec3 left_saber_base;
global uniform vec3 right_saber;
global uniform vec3 right_saber_base;
// Final light colour per side. The map's light-event tint is applied ONCE where these are
// written (BeepSaber_Game._apply_light_tint): it is lerp(saber, saber*tint, k) with a
// brightness floor, and nothing downstream multiplies a tint again (007 rule 6).
global uniform vec3 light_left;
global uniform vec3 light_right;
// 0/1 from Settings.floor_grid, as a global so one write drives every floor pixel.
global uniform float floor_grid;

uniform sampler2D burn_tex : source_color, filter_linear, repeat_disable;
// 0 when visual/floor_light is off: the burn trail is untouched, the streak is not.
uniform float streak_energy = 1.0;
// Metres from the blade's floor projection at which the pool reaches zero, and the
// full-brightness core. These two decide the size of the light, nothing else does.
uniform float streak_radius = 0.45;
uniform float streak_core = 0.06;
// Hit flash (FR-003): a point on the floor plane plus an energy that Floor._process decays.
// No node, no tween and no allocation is created for it.
uniform vec3 flash_pos = vec3(0.0, 0.0, -50.0);
uniform float flash_energy = 0.0;
uniform float flash_radius = 0.55;
uniform float grid_scale = 2.0;
// Faint on purpose: this is added to the same EMISSION the burn trail already drives, and
// anything stronger turns the pad into graph paper and starts to shimmer at distance.
uniform float grid_strength = 0.08;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 directly under the blade, 0 beyond streak_radius, squared so the falloff reads as
// light rather than as a painted stripe, and divided by height so a saber held high
// throws less onto the floor than one dragged along it.
float blade_streak(vec3 p, vec3 base, vec3 tip) {
	// A blade that is above the floor point cannot light it. Without this a retracted saber
	// parked far below the world maps to floor position (0,0) - the player's feet - and
	// paints a full-strength pool there. Also covers a blade dipped through the floor.
	if (max(base.y, tip.y) < p.y) {
		return 0.0;
	}
	vec2 a = base.xz;
	vec2 d = tip.xz - a;
	float dd = max(dot(d, d), 1e-6);
	float t = clamp(dot(p.xz - a, d) / dd, 0.0, 1.0);
	float dist = length(p.xz - (a + d * t));
	float k = 1.0 - smoothstep(streak_core, streak_radius, dist);
	float h = max(0.5 * (base.y + tip.y) - p.y, 0.0);
	return k * k / (1.0 + 0.9 * h * h);
}

// Faint anti-aliased grid (FR-006): one extra fwidth per floor pixel, in the pass the floor
// already runs. Width is measured in pixels, so the lines stay one to two pixels wide at
// any distance instead of aliasing into moire.
float floor_grid_lines(vec3 p) {
	if (floor_grid <= 0.0) {
		return 0.0;
	}
	vec2 c = p.xz * grid_scale;
	vec2 w = max(fwidth(c), vec2(1e-5));
	vec2 g = abs(fract(c) - 0.5) / w;
	return (1.0 - min(min(g.x, g.y), 1.0)) * grid_strength * floor_grid;
}

void fragment() {
	float l = blade_streak(world_pos, left_saber_base, left_saber);
	float r = blade_streak(world_pos, right_saber_base, right_saber);
	// Clamped so the worst case of every additive layer stacked stays bounded (007 rule 6).
	vec3 light = min((light_left * l + light_right * r) * streak_energy, vec3(1.5));
	// Radial burst at the cut point. No division and no eye vector, so a cut below the
	// floor or a blade at the camera cannot produce a NaN.
	float flash = 0.0;
	if (flash_energy > 0.0) {
		float d = length(world_pos.xz - flash_pos.xz);
		flash = (1.0 - smoothstep(0.0, flash_radius, d)) * flash_energy;
	}
	flash = min(flash, 1.0);
	// The burn trail is the same SubViewport texture the StandardMaterial3D used for
	// albedo and emission, with the same 6x boost floor.gd bakes into the sprites.
	vec3 burn = texture(burn_tex, UV).rgb;
	ALBEDO = burn;
	// 16x matches the floor.tscn emission energy (16, Multiply) that this replaces; the 6x
	// that floor.gd baked into the sprite modulate is not the same number, and using it here
	// made the burn trail ~2.7x dimmer than before. The 3x on the streak is the tuned look
	// from FR-045 and is kept as it was.
	EMISSION = burn * 16.0 + light * 3.0 + vec3(flash) + vec3(floor_grid_lines(world_pos));
}
