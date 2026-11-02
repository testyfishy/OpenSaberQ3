# Everything the hit sound is allowed to look at, captured at the moment of
# contact by the cuttable that scored the hit.
#
# Why it exists: the score components are computed *inside* `Cuttable.cut()`, and
# the sabre needs them for audio. Returning them keeps one source of truth for
# the maths instead of re-deriving accuracy in the sabre. See
# specs/002-hit-audio-research/research.md §3 and FR-011.
#
# A `null` HitInfo means "the cuttable had no hit data" (chain links today) and
# the sabre treats it as a light tap.
extends RefCounted
class_name HitInfo

enum Kind {
	GOOD, # right saber, scored
	BAD,  # wrong saber, or a bomb
}

var kind: Kind = Kind.GOOD

# |controller_speed| in m/s, measured over one physics tick (noisy, clamp it).
var speed_len := 0.0
# 0..1. 0 at ~45.6 deg off the cut direction, 1 at dead on. Always 1 for dots.
var angle_acc := 1.0
# 0..1. 0 at >=10 cm off the cut plane's centre.
var dist_acc := 1.0
# 0..1. Swing AABB length, trailing measure of the swing so far.
var travel := 1.0
# 0..1. 1 inside +/-0.25 m of the beat (the game's own 0.5 m window).
var beat_acc := 1.0
var is_correct_saber := true
var note_pos := Vector3.ZERO
