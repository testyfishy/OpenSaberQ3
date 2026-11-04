extends RefCounted
class_name NoteMotion

# The one place a note's forward speed is defined (v0.4 FR-006).
#
# Notes are spaced in beats, so the metres-per-second they travel is a property of the tempo in
# force at that note's beat - not of the map's base tempo. Before this, the same expression was
# repeated in five spawn paths, and a tempo-change fix had to be applied to all of them.

static func speed_at(beat: float) -> float:
	return Constants.BEAT_DISTANCE * Map.bpm_at_beat(beat) / 60.0
