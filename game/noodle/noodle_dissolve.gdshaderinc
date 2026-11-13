// Noodle Extensions `dissolve` (Heck: 1 = fully drawn, 0 = gone; Beat Saber draws it as a noise
// cutout). The fade is a per-pixel `discard` against object-space noise, so a dissolving object
// stays in the opaque pass and needs no blending or sorting. Object space, not screen space: the
// pattern sticks to the object as it moves and is the same in both eyes.
//
// Callers only reach this when their dissolve is below 1, so an object at 1 runs none of it.

float noodle_dissolve_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise in [0, 1), plus a little per-cell dither so the edge of a hole is not a hard line.
float noodle_dissolve_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(
		mix(mix(noodle_dissolve_hash(i), noodle_dissolve_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(noodle_dissolve_hash(i + vec3(0.0, 1.0, 0.0)), noodle_dissolve_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(noodle_dissolve_hash(i + vec3(0.0, 0.0, 1.0)), noodle_dissolve_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(noodle_dissolve_hash(i + vec3(0.0, 1.0, 1.0)), noodle_dissolve_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
	return clamp(n * 0.85 + noodle_dissolve_hash(p * 7.0) * 0.15, 0.0, 0.9999);
}

// True when this pixel is cut out at `dissolve`. `p` is the object-space position scaled so the
// object spans a few noise cells.
bool noodle_dissolved(vec3 p, float dissolve) {
	return noodle_dissolve_noise(p) >= dissolve;
}
