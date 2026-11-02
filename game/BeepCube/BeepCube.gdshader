// Note cube / cut piece material.
//
// Two things changed for specs/007-visual-options and both are about *sharing*:
//
//  * The neon edge glow is EMISSION here (FR-001), using the same box-edge mask as
//    shaders/neon_halo.gdshader, so a note glows without the separate halo shell mesh
//    that used to cost one extra draw and one extra material per note.
//  * Everything that varies per note is an `instance uniform` (FR-002/FR-004) and the
//    material is no longer `resource_local_to_scene`, so every live note shares one
//    ShaderMaterial, one shader and one instance-uniform block. The colour comes from
//    the map (per-note `_customData`, else the map's colour scheme, else settings).
//
// The edge mask compares a model-space position against the mesh AABB (`note_half_extent`)
// and ignores the axis the visible face is pinned to, because the third axis is +/-1 by
// construction on that face and would otherwise mask the whole face out.
shader_type spatial;
render_mode cull_disabled,diffuse_burley,specular_schlick_ggx;

instance uniform vec4 note_color : source_color;
instance uniform float note_is_dot = 0.0;
instance uniform float note_chain_head = 0.0;
// Half the mesh AABB in mesh space; set once per instance in _ready().
instance uniform vec3 note_half_extent = vec3(0.5, 0.5, 0.5);

uniform sampler2D texture_emission : hint_default_black;

uniform float metallic;
uniform float roughness;
uniform float sub_emission_energy;

// Edge glow (FR-001). A global so one write from Settings drives every note in the pool;
// 0 turns it into the exact pixels this shader drew before FR-001, with no recompile.
global uniform float note_edge_glow;
uniform float edge_start = 0.80;

uniform bool cutted = false;
uniform float cut_dist_from_center = 0.0;
uniform float cut_vanish = 0.0;
uniform float cut_angle = 0.0;
uniform float cut_white_margin = 0.04;

// [firepal]TODO: Build matrix on CPU (I tried but couldn't')
mat3 rotation3dZ(float angle) {
	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		vec3(c, s, 0.0),
		vec3(-s, c, 0.0),
		vec3(0.0, 0.0, 1.0)
	);
}

varying float cut_interp;
varying float chain_interp;
varying vec3 local_pos;
varying vec3 local_n;
void vertex() {
	// NORMAL is view space in the fragment stage; the edge mask compares it against a
	// mesh-space position, so the mesh-space normal has to be captured here.
	local_pos = VERTEX;
	local_n = NORMAL;
	if (note_chain_head > 0.5) {
		chain_interp = 0.1 + VERTEX.y;
	}
	if (cutted) {
		float cut_line = cut_dist_from_center+(VERTEX*rotation3dZ(cut_angle)).x;
		cut_interp = cut_line;
		cut_interp -= cut_vanish;
	}
}

void fragment() {
	// Discard all pixels "in the cut"
	if (
		(cutted && cut_interp < 0.0)
		|| (note_chain_head > 0.5 && chain_interp < 0.0)
	) {
		discard;
	}

	ALBEDO = note_color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (FRONT_FACING) {
		vec2 dot_uv = vec2(UV.x+0.5, UV.y);
		EMISSION = (note_color.rgb * sub_emission_energy) + texture(texture_emission, note_is_dot > 0.5 ? dot_uv : UV).rgb;

		if (note_chain_head > 0.5) {
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,chain_interp) );
		}

		if (cutted){
			// soft white margin
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,cut_interp) );
			// hard white margin
			//EMISSION += vec3( float(cut_white_margin < cut_interp) );
		}

		// Edge glow (FR-001): additive, so the note reads as neon without a second draw.
		// Branching on a global uniform costs nothing; a branchless version would pay the
		// mask maths on every note pixel even with the setting off.
		if (note_edge_glow > 0.0) {
			vec3 a = abs(local_pos) / max(note_half_extent, vec3(1e-4));
			// The two axes that vary across the face we are looking at: the third one is
			// pinned at +/-1 by the face itself and would otherwise mask everything out.
			vec3 axis_mask = 1.0 - step(vec3(0.5), abs(normalize(local_n)));
			float m = max(a.x * axis_mask.x, max(a.y * axis_mask.y, a.z * axis_mask.z));
			EMISSION += note_color.rgb * note_edge_glow * smoothstep(edge_start, 1.0, m);
		}
	} else {
		EMISSION = vec3(1.0);
	}
}
