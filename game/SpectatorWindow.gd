extends Window

@onready var score_view := $ScoreView as Control
@onready var point_label := $ScoreView/PointLabel as RichTextLabel
@onready var multiplier_label := $ScoreView/MultiplierLabel as RichTextLabel
@onready var percent_indicator := $ScoreView/SubViewportContainer/SubViewport/Camera3D/PercentIndicator as PercentIndicator

func _ready() -> void:
	@warning_ignore("return_value_discarded")
	visibility_changed.connect(resize_to_main_window_size)
	visible = Settings.spectator_view
	@warning_ignore("return_value_discarded")
	close_requested.connect(close)
	Scoreboard.score_changed.connect(on_scoreboard_update)

func resize_to_main_window_size() -> void:
	if visible:
		size = get_tree().get_root().size

func on_scoreboard_update() -> void:
	if not visible: return
	
	var hit_rate: float
	if Scoreboard.right_notes+Scoreboard.wrong_notes > 0:
		hit_rate = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	else:
		hit_rate = 1.0
	
	point_label.text = "Score: %6d" % Scoreboard.points
	multiplier_label.text = "x %d\nCombo %d" % [Scoreboard.multiplier, Scoreboard.combo]
	percent_indicator.update_percent(hit_rate)

func close() -> void:
	visible = false
