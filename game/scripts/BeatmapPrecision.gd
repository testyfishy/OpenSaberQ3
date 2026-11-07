extends RefCounted
class_name BeatmapPrecision

## Mapping Extensions decoding (specs/027 FR-005/006).
##
## - Positions: |raw| >= 1000 is precise. 1000 and -1000 are lane 0; 2000 = lane 1, -2000 = lane -1;
##   each unit is 1/1000 of a lane.
## - Cut direction 1000..1360: 0..360 degrees clockwise, 0 = down, 90 = left, 180 = up.
##   Any-direction is 2000..2360 (same angles, direction ignored for scoring).
## - Wall width: raw >= 1000, 1000 = 0 width, 2000 = 1.
## - Wall type 1000..4000: height = (type - 1000) / 1000 * 5 layers, start at the floor.
## - Wall type 4001..4005000: type = height*1000 + start + 4001, height 0..4000 (literal),
##   start 0..999. Approximated as layers of 1/1000.

const POS_OFFSET := 1000.0
const POS_SCALE := 1000.0

static func is_precise(raw: float) -> bool:
	return absf(raw) >= POS_OFFSET

## Lane/layer coordinate. 1000 -> 0, 2000 -> 1, -2000 -> -1.
static func decode_position(raw: float) -> float:
	if raw >= POS_OFFSET:
		return (raw - POS_OFFSET) / POS_SCALE
	if raw <= -POS_OFFSET:
		return (raw + POS_OFFSET) / POS_SCALE
	return raw

## Width/size. 1000 -> 0, 2000 -> 1; values below 1000 are already sizes.
static func decode_size(raw: float) -> float:
	if raw >= POS_OFFSET:
		return (raw - POS_OFFSET) / POS_SCALE
	return raw

## Returns {"angle": degrees clockwise from down, "any": bool} for a precise cut direction,
## or {} for the normal 0..8 directions.
static func cut_angle(raw: int) -> Dictionary:
	if raw >= 2000 and raw <= 2360:
		return {"angle": float(raw - 2000), "any": true}
	if raw >= 1000 and raw <= 1360:
		return {"angle": float(raw - 1000), "any": false}
	return {}

## Wall height (layers) and start layer from an ME type, or {} for a normal type 0/1/2.
static func wall_height(raw: int) -> Dictionary:
	if raw >= 4001 and raw <= 4005000:
		var v := raw - 4001
		var height_units := v / 1000
		var start_units := v % 1000
		# Literal height units: 1000 is one layer; start 250 is about a quarter layer, matching the
		# mod's "start height of 250 is just above a normal wall" convention.
		return {"height": float(height_units) / 1000.0, "layer": float(start_units) / 1000.0}
	if raw >= 1000 and raw <= 4000:
		return {"height": float(raw - 1000) / 1000.0 * 5.0, "layer": 0.0}
	return {}
