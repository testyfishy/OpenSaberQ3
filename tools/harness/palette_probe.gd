extends Node

func _ready() -> void:
	var folder := "F:/Dev/BeepSaberBin/map-corpus/Songs/livetune feat. Hatsune Miku - Hand in Hand [V3LightsCinema]/"
	var info_text := FileAccess.get_file_as_string(folder + "Info.dat")
	var diff_text := FileAccess.get_file_as_string(folder + "ExpertPlusStandard.dat")
	var info_dict: Dictionary = JSON.parse_string(info_text)
	var diff_dict: Dictionary = JSON.parse_string(diff_text)
	var info := MapInfo.new_v2(info_dict, folder)
	var diff := DifficultyInfo.load_v2(diff_dict)
	MapPalette.set_colors_from_custom_data(info, diff)
	print("PALETTEPROBE env=%s wall=%s left=%s right=%s" % [
		MapPalette.environment_name, str(MapPalette.wall_color), str(MapPalette.color_left),
		str(MapPalette.color_right)])
	get_tree().quit()
