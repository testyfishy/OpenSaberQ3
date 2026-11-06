extends Node3D

# Chain cut-order test (specs/019 FR-003/SC-006).
#
# Builds real ChainLink scenes through spawn(), registers their hitboxes with the analytic
# resolver, and sweeps a blade along the chain (straight and curved). Every link must be cut, in
# head-to-tail order, and the scoring call is the game's own Scoreboard.chain_link_cut.
#
# Run: godot --headless --path . res://tools/tests/test_chain_cut.tscn

const LINK_SCENE := preload("res://game/Chain/ChainLink.tscn")
const HitResolver := preload("res://game/scripts/HitResolver.gd")
const BLADE := 1.26
const LINK_LAYER := 768  # ChainLink.tscn: bit 8 + LeftNote (bit 9)
const TICKS := 120

var _bad := 0

func _ready() -> void:
	Map.current_difficulty = DifficultyInfo.new("ExpertPlus", 9, "x.dat", 16.0, 0.0, {}, "One")
	MapPalette.color_left = Color(1, 0, 0)
	MapPalette.color_right = Color(0, 0, 1)
	await _check_chain("straight", 0.0, 0.0, 0.0, 0.0, 1)
	await _check_chain("curved", 0.0, 0.0, 2.0, 1.5, 2)
	print("CHAINGCUT ", "PASS" if _bad == 0 else "FAIL")
	get_tree().quit(0 if _bad == 0 else 1)

func _check_chain(label: String, hx: float, hy: float, tx: float, ty: float, cut_dir: int) -> void:
	var slices := 8
	var chain := ChainInfo.new(
		0, 0.0, 0, 0, cut_dir,
		1.0, 0, 0, slices, 1.0)
	var head_pos := Vector2(hx, hy)
	var tail_pos := Vector2(tx, ty)
	var mid_pos := head_pos + Constants.ROTATION_UNIT_VECTORS[chain.head_cut_direction] * head_pos.distance_to(tail_pos) * 0.5

	Scoreboard.restart()
	var links: Array[ChainLink] = []
	for i in range(1, slices):
		var link := LINK_SCENE.instantiate() as ChainLink
		add_child(link)
		link.spawn(chain, 0.0, head_pos, tail_pos, mid_pos, i)
		HitResolver.add(link, LINK_LAYER, link.get_node("Area3D/CollisionShape3D") as CollisionShape3D)
		links.append(link)

	var start := ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, 0.0, 0.0)
	var first_dir := (ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, 0.02, 0.0) - start).normalized()
	var prev_tip := start - first_dir * 0.3
	var prev_base := prev_tip - first_dir * BLADE
	var cut: Array[ChainLink] = []
	for tick in TICKS:
		var u := float(tick + 1) / float(TICKS)
		# Follow the chain curve, not its chord: a curved chain leaves the chord.
		var tip := ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, chain.squish_factor * u, 0.0)
		var ahead := ChainLink.chain_point(chain, head_pos, mid_pos, tail_pos, clampf(chain.squish_factor * (u + 0.01), 0.0, 1.0), 0.0)
		var axis := (ahead - tip).normalized()
		if axis.length_squared() < 0.0001:
			axis = first_dir
		var base := tip - axis * BLADE
		var hit := HitResolver.find_hit(LINK_LAYER, prev_base, prev_tip, base, tip)
		if hit != null:
			var link := hit as ChainLink
			if link != null and not cut.has(link):
				cut.append(link)
				Scoreboard.chain_link_cut(link.global_position)
				HitResolver.remove(link)
		prev_tip = tip
		prev_base = base

	_check(cut.size() == links.size(), "%s: cut %d of %d links" % [label, cut.size(), links.size()])
	for i in links.size():
		if i < cut.size():
			_check(cut[i] == links[i], "%s: link %d cut in order" % [label, i + 1])
	var want_points := 0
	for i in cut.size():
		want_points += 20 * mini(1 + i / 10, 8)
	_check(Scoreboard.points == want_points, "%s: score %d (want %d)" % [label, Scoreboard.points, want_points])

	for link in links:
		HitResolver.remove(link)
		link.queue_free()
	HitResolver.clear()
	await get_tree().process_frame

func _check(condition: bool, what: String) -> void:
	if not condition:
		push_error("CHAINGCUT " + what)
		_bad += 1
