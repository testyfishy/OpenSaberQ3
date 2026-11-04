extends Node

func _ready() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://bench.flag")
	print("FLAGTEST err=", err, " (", error_string(err), ")")
	if err == OK:
		for section in cfg.get_sections():
			print("  [", section, "] ", cfg.get_section_keys(section))
	get_tree().quit()
