shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Debris shards (spec FR-013). One MultiMesh draws the whole pool; the vertex stage is the
// only place the shards move, and it is driven entirely by per-instance data:
//   INSTANCE_CUSTOM = (birth_time, vx, vy, vz)  written once per cut
//   COLOR          = the note colour
// Dead slots collapse to a point (zero area), so nothing has to be hidden or disabled.

uniform float now = 0.0;
uniform float life = 0.5;
uniform float gravity = -9.8;

varying vec3 shard_color;

void vertex() {
	float birth = INSTANCE_CUSTOM.x;
	vec3 vel = INSTANCE_CUSTOM.yzw;
	float t = now - birth;
	float alive = step(0.0, t) * (1.0 - step(life, t));
	float tt = clamp(t, 0.0, life);

	// Ballistic flight, in the instance's local frame. The instance transform is a pure
	// translation, so local and world directions are the same.
	vec3 motion = vel * tt + vec3(0.0, 0.5 * gravity * tt * tt, 0.0);

	// Tumble: a per-shard axis and rate hashed from the instance id and its birth time, so two
	// bursts in the same slots do not spin identically.
	float h = fract(sin(float(INSTANCE_ID) * 12.9898 + birth * 78.233) * 43758.5453);
	vec3 axis = normalize(vec3(h - 0.5, fract(h * 7.13) - 0.5, fract(h * 13.71) - 0.5) + vec3(0.001));
	float angle = (7.0 + h * 9.0) * tt;
	vec3 v = VERTEX;
	v = v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));

	// Fade by shrinking to nothing: opaque, so no blend and no sort cost.
	float shrink = 1.0 - smoothstep(life * 0.65, life, tt);
	VERTEX = (v * shrink + motion) * alive;

	shard_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = shard_color;
}
