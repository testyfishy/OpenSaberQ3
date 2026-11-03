extends Node3D
class_name BeepCubeSliceParticles

# Hard debris cap (specs/007-visual-options FR-010, default off).
#
# One particle budget for the whole game. Each burst costs a fixed number of particles, so the
# cap is simply "how many bursts may be alive at once": a burst that does not fit is not fired
# at all. The bookkeeping is a preallocated ring of expiry times, compacted in place on each
# fire - no allocation per cut, no timer node and no per-frame work, which is what the "no new
# cost to bound cost" rule asks for.
const DEBRIS_BUDGET := 120
# Particles per burst. With the cap on the burst is halved, so the same 120 particles buy four
# bursts instead of two and a dense section still shows debris.
const CAPPED_PARTICLES := 30
const UNCAPPED_PARTICLES := 60
const BURSTS_MAX := 32
# How long a burst holds its share of the budget: the particle lifetime plus the max
# `lifetime_randomness` (0.3) and a little slack.
const BURST_HOLD := 1.2

static var _burst_ends := PackedFloat64Array()
static var _bursts := 0

@onready var c1 := $Particles3D as GPUParticles3D

func _ready() -> void:
	c1.one_shot = true
	#disable gpu particles since they don't work correctly on android
	if OS.get_name() in ["Android","Web"]:
		c1.free()
	reset()

func reset() -> void:
	if not is_instance_valid(c1): return
	visible = false
	c1.emitting = false
	c1.restart()

func fire() -> void:
	if not is_instance_valid(c1): return
	# Particle count is set here only when it differs from the setting's value: changing
	# `amount` reallocates the particle buffer, so it must not happen on every cut.
	var target := CAPPED_PARTICLES if Settings.debris_cap else UNCAPPED_PARTICLES
	if int(c1.amount) != target:
		c1.amount = target
	if Settings.debris_cap and not _claim_burst():
		# Over budget: the burst is dropped. Nothing was created for it, so there is nothing
		# to free - the node stays hidden until its note is recycled.
		return
	visible = true
	c1.emitting = true

# Called when the setting is toggled, so a budget filled under the old setting does not hold
# the new one back for a second.
static func apply_cap_setting() -> void:
	_bursts = 0

static func _claim_burst() -> bool:
	if _burst_ends.size() != BURSTS_MAX:
		# One-time allocation; every later call resizes nothing.
		_burst_ends.resize(BURSTS_MAX)
	var now := Time.get_ticks_msec() * 0.001
	var i := 0
	while i < _bursts:
		if _burst_ends[i] <= now:
			_bursts -= 1
			_burst_ends[i] = _burst_ends[_bursts]
		else:
			i += 1
	var allowed := maxi(DEBRIS_BUDGET / maxi(CAPPED_PARTICLES, 1), 1)
	if _bursts >= allowed or _bursts >= BURSTS_MAX:
		return false
	_burst_ends[_bursts] = now + BURST_HOLD
	_bursts += 1
	return true
