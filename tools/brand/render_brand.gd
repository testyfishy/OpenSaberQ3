extends SceneTree

# Renders the brand SVG masters to the PNG sizes the project uses.
# Run: godot --headless --path . -s res://tools/brand/render_brand.gd
# Keep the SVGs in docs/brand/ as the source of truth; this script only rasterises.

const JOBS := [
	["res://docs/brand/logo.svg", "res://icon.png", 1.0],
	["res://docs/brand/logo-small.svg", "res://icon_192.png", 0.375],
	["res://docs/brand/icon-adaptive-fg.svg", "res://icon_adaptive_fg_432.png", 1.0],
	["res://docs/brand/icon-adaptive-bg.svg", "res://icon_adaptive_bg_432.png", 1.0],
	["res://docs/brand/logo.svg", "res://game/data/beepsaber_logo.png", 1.0],
	["res://docs/brand/banner.svg", "res://docs/images/banner.png", 1.0],
	["res://docs/brand/banner.svg", "res://docs/images/cover.png", 1.0],
	["res://docs/brand/itch-cover.svg", "res://docs/images/itch-cover.png", 1.0],
	["res://docs/brand/logo.svg", "res://docs/images/logo.png", 1.0],
	["res://docs/brand/wordmark-horizontal.svg", "res://docs/brand/wordmark-horizontal.png", 1.0],
	["res://docs/brand/wordmark-stacked.svg", "res://docs/brand/wordmark-stacked.png", 1.0],
]

func _initialize() -> void:
	var failed := 0
	for job in JOBS:
		var source := FileAccess.get_file_as_string(job[0])
		if source.is_empty():
			print("BRAND missing ", job[0])
			failed += 1
			continue
		var img := Image.new()
		var err := img.load_svg_from_string(source, float(job[2]))
		if err != OK:
			print("BRAND error ", job[0], " -> ", err)
			failed += 1
			continue
		err = img.save_png(job[1])
		if err != OK:
			print("BRAND save error ", job[1], " -> ", err)
			failed += 1
			continue
		print("BRAND ", job[1], " ", img.get_width(), "x", img.get_height())
	print("BRAND done failures=", failed)
	quit(0 if failed == 0 else 1)
