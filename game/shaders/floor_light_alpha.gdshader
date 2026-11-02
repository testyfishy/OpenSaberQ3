// Analytic saber light on the floor (specs/001-quest3-saber-perf FR-045).
//
// The floor already carries the burn trail from a SubViewport; this shader keeps that
// texture and adds a closed-form "light pool" under each blade. There is no second
// viewport, no shadow map and no scene query: the only inputs are the four world-space
// points the sabers publish once per physics tick (see project.godot [shader_globals]
// and LightSaber._physics_process).
//
// Stereo: world_pos comes from MODEL_MATRIX, which carries no eye offset, so both eyes
// sample the same world point on the plane and the streak stays glued to the floor. An
// eye-dependent quantity here would make the light swim between the eyes.
shader_type spatial;
render_mode blend_mix, cull_back;

// Both blades, base and tip, in world space (tip = the existing left_saber/right_saber).
global uniform vec3 left_saber;
global uniform vec3 left_saber_base;
global uniform vec3 right_saber;
global uniform vec3 right_saber_base;

uniform sampler2D burn_tex : source_color, filter_linear, repeat_disable;
uniform vec3 left_color : source_color = vec3(1.0, 0.1, 0.1);
uniform vec3 right_color : source_color = vec3(0.1, 0.1, 1.0);
// 0 when visual/floor_light is off: the burn trail is untouched, the streak is not.
uniform float streak_energy = 1.0;
// Metres from the blade's floor projection at which the pool reaches zero, and the
// full-brightness core. These two decide the size of the light, nothing else does.
uniform float streak_radius = 0.45;
uniform float streak_core = 0.06;
// 1.0 keeps the floor opaque; the mirror setting drops it so the copies below show.
uniform float floor_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 directly under the blade, 0 beyond streak_radius, squared so the falloff reads as
// light rather than as a painted stripe, and divided by height so a saber held high
// throws less onto the floor than one dragged along it.
float blade_streak(vec3 p, vec3 base, vec3 tip) {
	// See floor_light.gdshader: without this a retracted saber paints a pool at the feet.
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

void fragment() {
	float l = blade_streak(world_pos, left_saber_base, left_saber);
	float r = blade_streak(world_pos, right_saber_base, right_saber);
	vec3 light = (left_color * l + right_color * r) * streak_energy;
	// The burn trail is the same SubViewport texture the StandardMaterial3D used for
	// albedo and emission, with the same 6x boost floor.gd bakes into the sprites.
	vec3 burn = texture(burn_tex, UV).rgb;
	ALBEDO = burn;
	// 16x matches the floor.tscn emission energy (16, Multiply) that this replaces; the 6x
	// that floor.gd baked into the sprite modulate is not the same number, and using it here
	// made the burn trail ~2.7x dimmer than before.
	EMISSION = burn * 16.0 + light * 3.0;
	ALPHA = floor_alpha;
}

