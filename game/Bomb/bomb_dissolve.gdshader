// Bomb body while a Noodle `dissolve` is below 1 (game/Bomb/Bomb.gd swaps it in, and swaps the
// scene's StandardMaterial3D back at 1). It reproduces that material: black albedo, per-vertex
// lighting, no ambient light, StandardMaterial3D defaults otherwise, plus the noise cutout.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, vertex_lighting, ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform float bomb_dissolve = 1.0;

#include "res://game/noodle/noodle_dissolve.gdshaderinc"

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// About three noise cells across the bomb mesh, like a note; a thin rim at the cut.
	float rim = 0.0;
	if (bomb_dissolve < 1.0) {
		rim = noodle_dissolve_edge(local_pos * 1.5, bomb_dissolve);
		if (rim < 0.0) {
			discard;
		}
	}
	ALBEDO = albedo.rgb;
	EMISSION = vec3(0.75) * rim;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = 1.0;
}
