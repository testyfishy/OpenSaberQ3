extends RefCounted
class_name TrackLanes

## 360/90 lanes (specs/027 FR-006, G4 0.7.2).
##
## Each object keeps the rotation that was in effect at its own beat for its whole flight, exactly
## like Beat Saber: a note spawned after a rotation event lives in a lane rotated by that event and
## flies down it; a note already in flight does not turn when the next event arrives. Lanes are
## Node3D children of the game's track, one per cumulative angle; the player and the room stay put.

static var _by_track: Dictionary = {}

static func lane_for(track: Node3D, beat: float) -> Node3D:
	var angle := Map.track_rotation_at(beat)
	var key := int(roundf(angle * 10.0))
	var lanes: Dictionary = _by_track.get(track, {})
	if not lanes.has(key):
		var lane := Node3D.new()
		lane.name = "Lane%d" % key
		lane.rotation.y = deg_to_rad(-angle)
		track.add_child(lane)
		lanes[key] = lane
		_by_track[track] = lanes
	return lanes[key] as Node3D

## Moves an object into the lane for its beat. Must be called after it is in the tree (the pools
## create their nodes under the track).
static func place(obj: Node3D, beat: float) -> void:
	if obj == null:
		return
	var parent := obj.get_parent()
	if parent == null:
		return
	var track: Node3D = parent as Node3D
	if parent.name.begins_with("Lane"):
		track = parent.get_parent() as Node3D
	if track == null:
		return
	var lane := lane_for(track, beat)
	if obj.get_parent() != lane:
		# keep_global_transform = false: spawn() has already written the object's transform in
		# lane-local coordinates. The default (keep the global transform) cancelled the lane's
		# rotation on the way in, and left a pooled node rotated on the way back to Lane0.
		obj.reparent(lane, false)
