// Noodle Extensions `dissolve` (Heck: 1 = fully drawn, 0 = gone). Heck hands Beat Saber's note
// shader a cutout of `1 - dissolve`, and that shader cuts a pixel where its noise texture is below
// the cutout, so holes open where the noise is lowest and grow as dissolve falls. Done here as a
// per-pixel `discard` against object-space noise, so a dissolving object stays in the opaque pass
// and needs no blending or sorting. Object space, not screen space: the pattern sticks to the
// object as it moves and is the same in both eyes.
//
// The noise is smooth and coarse (a few blobs across an object, two octaves, no per-pixel
// dither), so a partly dissolved object loses whole patches from a few seeds instead of being
// sprinkled with single-pixel holes. Smooth value noise rarely reaches its extremes, so above
// about 0.8 an object is nearly solid, and below about 0.2 nearly gone.
//
// Callers only reach this when their dissolve is below 1, so an object at 1 runs none of it.

// Width, in noise units, of the bright rim callers may draw along a cut edge.
const float NOODLE_DISSOLVE_RIM = 0.035;

float noodle_dissolve_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noodle_dissolve_value(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(noodle_dissolve_hash(i), noodle_dissolve_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(noodle_dissolve_hash(i + vec3(0.0, 1.0, 0.0)), noodle_dissolve_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(noodle_dissolve_hash(i + vec3(0.0, 0.0, 1.0)), noodle_dissolve_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(noodle_dissolve_hash(i + vec3(0.0, 1.0, 1.0)), noodle_dissolve_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// Smooth noise in [0, 1): a coarse octave for the blobs and a finer one so their edges are not
// perfectly round. No per-pixel term.
float noodle_dissolve_noise(vec3 p) {
	return noodle_dissolve_value(p) * 0.68 + noodle_dissolve_value(p * 2.07 + vec3(11.3, 5.7, 3.1)) * 0.32;
}

// -1 when this pixel is cut out at `dissolve`; otherwise how close it is to the cut edge, 1 right
// at the edge falling to 0 at NOODLE_DISSOLVE_RIM inside the surface. `p` is the object-space
// position scaled so the object spans a few noise cells.
float noodle_dissolve_edge(vec3 p, float dissolve) {
	float above = noodle_dissolve_noise(p) - (1.0 - dissolve);
	if (above < 0.0) {
		return -1.0;
	}
	return 1.0 - smoothstep(0.0, NOODLE_DISSOLVE_RIM, above);
}

// True when this pixel is cut out at `dissolve`.
bool noodle_dissolved(vec3 p, float dissolve) {
	return noodle_dissolve_noise(p) < 1.0 - dissolve;
}
