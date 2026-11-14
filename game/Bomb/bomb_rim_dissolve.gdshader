// Bomb outline shell while a Noodle `dissolve` is below 1 (see bomb_dissolve.gdshader). It
// reproduces the scene's StandardMaterial3D: unshaded, front faces culled, grown along the normal.
// The noise uses the position before the grow, so the shell's holes line up with the body's.
// While dissolving, only the side-on rim of the shell is drawn (see fragment()).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform vec4 albedo : source_color = vec4(1.0, 0.0, 0.0980392, 1.0);
uniform float grow = 0.09;
instance uniform float bomb_dissolve = 1.0;

#include "res://game/noodle/noodle_dissolve.gdshaderinc"

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	VERTEX += NORMAL * grow;
}

void fragment() {
	if (bomb_dissolve < 1.0) {
		// The shell is the inside of a grown copy of the body, so its outline is the part seen
		// side-on at the silhouette. Through the body's dissolve holes the far side of the shell
		// would face the camera head-on and show as red patches inside the bomb: drop those.
		if (noodle_dissolved(local_pos * 1.5, bomb_dissolve) || abs(dot(normalize(NORMAL), VIEW)) > 0.55) {
			discard;
		}
	}
	ALBEDO = albedo.rgb;
}
