// Static gradient sky (specs/007-visual-options FR-007).
//
// Replaces the panorama when Settings.sky_gradient is on (default off: it replaces the game's
// background art, so the player chooses it). No texture fetch at all, and the shader uses no
// TIME, which is what makes it a one-off render: Sky.PROCESS_MODE_AUTOMATIC sees no time
// dependency and does not redraw it, so the radiance cubemap behind it is generated once and
// regenerated only when the setting changes (BeepSaber_Game._apply_sky swaps the whole Sky
// resource, which is the "updating only on load/setting change" rule).
//
// BeepSaber_Game builds the Sky with radiance_size = RADIANCE_SIZE_32, the smallest the
// engine offers, because ambient filtering cost scales with that cubemap and this gradient
// has no detail for a larger one to resolve.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.035, 0.055, 0.13);
uniform vec3 horizon_color : source_color = vec3(0.20, 0.13, 0.30);
uniform vec3 ground_color : source_color = vec3(0.02, 0.02, 0.035);
// How tightly the horizon colour is squeezed around y = 0. Higher = tighter band.
uniform float horizon_sharpness = 2.5;
// Overall scale, so the gradient can be matched to the panorama's brightness.
uniform float energy = 1.0;

void sky() {
	float y = EYEDIR.y;
	vec3 c;
	if (y >= 0.0) {
		c = mix(horizon_color, top_color, pow(clamp(y, 0.0, 1.0), 1.0 / horizon_sharpness));
	} else {
		// Below the horizon: a dim floor colour, blended the same way, so looking down does
		// not show a hard seam at y = 0. pow() of a positive number keeps this NaN-free.
		c = mix(horizon_color, ground_color, pow(clamp(-y, 0.0, 1.0), 1.0 / horizon_sharpness));
	}
	COLOR = c * energy;
}
