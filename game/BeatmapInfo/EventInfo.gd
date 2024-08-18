extends RefCounted
class_name EventInfo

var beat: float
var type: int
var value: int
var float_value: float

@warning_ignore("shadowed_variable")
func _init(beat: float, type: int, value: int, float_value: float) -> void:
	self.beat = beat
	self.type = type
	self.value = value
	self.float_value = float_value

static func new_v2(event_dict: Dictionary) -> EventInfo:
	return EventInfo.new(
		Utils.get_float(event_dict, "_time", 0.0),
		int(Utils.get_float(event_dict, "_type", 0)),
		int(Utils.get_float(event_dict, "_value", 0)),
		Utils.get_float(event_dict, "_floatValue", -1.0)
	)

static func new_v3(event_dict: Dictionary) -> EventInfo:
	return EventInfo.new(
		Utils.get_float(event_dict, "b", 0.0),
		int(Utils.get_float(event_dict, "et", 0)),
		int(Utils.get_float(event_dict, "i", 0)),
		Utils.get_float(event_dict, "f", -1.0)
	)
