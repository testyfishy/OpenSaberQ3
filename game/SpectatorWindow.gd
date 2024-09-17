extends Window

func _ready() -> void:
	visible = Settings.spectator_view
	resize_to_main_window_size()
	@warning_ignore("return_value_discarded")
	visibility_changed.connect(resize_to_main_window_size)
	@warning_ignore("return_value_discarded")
	close_requested.connect(close)

func resize_to_main_window_size() -> void:
	if visible:
		size = get_tree().get_root().size

func close() -> void:
	visible = false
