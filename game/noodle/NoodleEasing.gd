extends RefCounted
class_name NoodleEasing

# The easing functions Heck (Noodle Extensions' animation library) uses for point definitions
# and for the `easing` field of AnimateTrack / AssignPathAnimation.
#
# These are ported from Heck/Animation/Easings.cs (MIT, Copyright (c) 2021 Aeroluna), not from
# easings.net: several differ from the easings.net formulas (easeInBack, easeInExpo and
# easeOutExpo are normalised so they land exactly on 0 and 1, easeInOutExpo passes values above
# 1 through), and a map is authored against what Heck does.
#
# Ids are ints so the per-tick code never touches a string. Unknown names read as linear.

enum {
	LINEAR, STEP,
	IN_QUAD, OUT_QUAD, IN_OUT_QUAD,
	IN_CUBIC, OUT_CUBIC, IN_OUT_CUBIC,
	IN_QUART, OUT_QUART, IN_OUT_QUART,
	IN_QUINT, OUT_QUINT, IN_OUT_QUINT,
	IN_SINE, OUT_SINE, IN_OUT_SINE,
	IN_CIRC, OUT_CIRC, IN_OUT_CIRC,
	IN_EXPO, OUT_EXPO, IN_OUT_EXPO,
	IN_ELASTIC, OUT_ELASTIC, IN_OUT_ELASTIC,
	IN_BACK, OUT_BACK, IN_OUT_BACK,
	IN_BOUNCE, OUT_BOUNCE, IN_OUT_BOUNCE,
}

const NAMES := {
	"easeLinear": LINEAR, "easeStep": STEP,
	"easeInQuad": IN_QUAD, "easeOutQuad": OUT_QUAD, "easeInOutQuad": IN_OUT_QUAD,
	"easeInCubic": IN_CUBIC, "easeOutCubic": OUT_CUBIC, "easeInOutCubic": IN_OUT_CUBIC,
	"easeInQuart": IN_QUART, "easeOutQuart": OUT_QUART, "easeInOutQuart": IN_OUT_QUART,
	"easeInQuint": IN_QUINT, "easeOutQuint": OUT_QUINT, "easeInOutQuint": IN_OUT_QUINT,
	"easeInSine": IN_SINE, "easeOutSine": OUT_SINE, "easeInOutSine": IN_OUT_SINE,
	"easeInCirc": IN_CIRC, "easeOutCirc": OUT_CIRC, "easeInOutCirc": IN_OUT_CIRC,
	"easeInExpo": IN_EXPO, "easeOutExpo": OUT_EXPO, "easeInOutExpo": IN_OUT_EXPO,
	"easeInElastic": IN_ELASTIC, "easeOutElastic": OUT_ELASTIC, "easeInOutElastic": IN_OUT_ELASTIC,
	"easeInBack": IN_BACK, "easeOutBack": OUT_BACK, "easeInOutBack": IN_OUT_BACK,
	"easeInBounce": IN_BOUNCE, "easeOutBounce": OUT_BOUNCE, "easeInOutBounce": IN_OUT_BOUNCE,
}

const HALF_PI := PI / 2.0
# Mathf.Epsilon in Unity is the smallest positive float.
const TINY := 1.4e-45


static func from_name(name: Variant) -> int:
	if name is String or name is StringName:
		return int(NAMES.get(String(name), LINEAR))
	return LINEAR


static func ease(p: float, id: int) -> float:
	match id:
		LINEAR: return p
		STEP: return floorf(p)
		IN_QUAD: return p * p
		OUT_QUAD: return (2.0 - p) * p
		IN_OUT_QUAD:
			var x := p - 0.5
			return (x - x * absf(x)) * 2.0 + 0.5
		IN_CUBIC: return p * p * p
		OUT_CUBIC:
			var f := 1.0 - p
			return 1.0 - f * f * f
		IN_OUT_CUBIC:
			var f := p - 0.5
			var x := absf(f)
			return (((4.0 * x - 6.0) * x + 3.0) * f) + 0.5
		IN_QUART: return p * p * p * p
		OUT_QUART:
			var f := 1.0 - p
			return 1.0 - f * f * f * f
		IN_OUT_QUART:
			var f := p - 0.5
			var x := absf(f)
			var t := x * -8.0 + 16.0
			t = t * x - 12.0
			t = t * x + 4.0
			return t * f + 0.5
		IN_QUINT: return p * p * p * p * p
		OUT_QUINT:
			var f := 1.0 - p
			return 1.0 - f * f * f * f * f
		IN_OUT_QUINT:
			var f := p - 0.5
			var x := absf(f)
			var t := x * 16.0 - 40.0
			t = t * x + 40.0
			t = t * x - 20.0
			t = t * x + 5.0
			return t * f + 0.5
		IN_SINE: return 1.0 - cos(HALF_PI * p)
		OUT_SINE: return sin(p * HALF_PI)
		IN_OUT_SINE:
			var f := sin(HALF_PI * p)
			return f * f
		IN_CIRC: return 1.0 - sqrt(maxf(TINY, 1.0 - p * p))
		OUT_CIRC: return sqrt(maxf(TINY, (2.0 - p) * p))
		IN_OUT_CIRC:
			if p < 0.5:
				return 0.5 - sqrt(maxf(TINY, 0.25 - p * p))
			var q := p - 1.0
			return 0.5 + sqrt(maxf(TINY, 0.25 - q * q))
		IN_EXPO:
			return p if p <= 0.0 else (pow(2.0, 10.0 * p) / 1023.0) - (1.0 / 1023.0)
		OUT_EXPO:
			const S := 1024.0 / 1023.0
			return p if p > 1.0 else S - S * pow(2.0, -10.0 * p)
		IN_OUT_EXPO:
			if p > 1.0:
				return p
			var q := p * 20.0 - 10.0
			const S := 512.0 / 1023.0
			if q < 0.0:
				return 0.5 - (S - S * pow(2.0, q))
			return 0.5 + (S - S * pow(2.0, -q))
		IN_ELASTIC: return sin(13.0 * HALF_PI * p) * pow(2.0, 10.0 * (p - 1.0))
		OUT_ELASTIC: return sin(-13.0 * HALF_PI * (p + 1.0)) * pow(2.0, -10.0 * p) + 1.0
		IN_OUT_ELASTIC:
			if p < 0.5:
				return 0.5 * sin(13.0 * HALF_PI * (2.0 * p)) * pow(2.0, 10.0 * (2.0 * p - 1.0))
			return 0.5 * (sin(-13.0 * HALF_PI * (2.0 * p)) * pow(2.0, -10.0 * (2.0 * p - 1.0)) + 2.0)
		IN_BACK: return p * p * p - p * sin(p * PI)
		OUT_BACK:
			var f := 1.0 - p
			return 1.0 - (f * f * f - f * sin(f * PI))
		IN_OUT_BACK:
			if p < 0.5:
				var f := 2.0 * p
				return 0.5 * (f * f * f - f * sin(f * PI))
			var g := 1.0 - (2.0 * p - 1.0)
			return 0.5 * (1.0 - (g * g * g - g * sin(g * PI))) + 0.5
		IN_BOUNCE: return 1.0 - _out_bounce(1.0 - p)
		OUT_BOUNCE: return _out_bounce(p)
		IN_OUT_BOUNCE:
			if p < 0.5:
				return 0.5 * (1.0 - _out_bounce(1.0 - p * 2.0))
			return 0.5 * _out_bounce(p * 2.0 - 1.0) + 0.5
	return p


static func _out_bounce(p: float) -> float:
	var x := (121.0 / 16.0) * p * p
	var q1 := p - 6.0 / 11.0
	x = minf(x, (363.0 / 40.0) * q1 * q1 + 7.0 / 10.0)
	var q2 := p - 179.0 / 220.0
	x = minf(x, (4356.0 / 361.0) * q2 * q2 + 91.0 / 100.0)
	var q3 := p - 19.0 / 20.0
	x = minf(x, (54.0 / 5.0) * q3 * q3 + 973.0 / 1000.0)
	return x
