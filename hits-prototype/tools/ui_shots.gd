extends SceneTree
## UI review: saddle view, telescope, map (zoomed out and in) and order of
## battle, on the full battle after the armies have deployed. Needs a window:
##   godot --path hits-prototype --resolution 1600x900 --script res://tools/ui_shots.gd -- --out=DIR

var battle
var out := "."
var frame := 0
var steps: Array
var _shot_in := 0
var _shot_name := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	root.get_node("GameState").scenario = 0  # BENCHMARK
	battle = load("res://battle.tscn").instantiate()
	root.add_child(battle)
	# [sim seconds, action, screenshot name or ""]
	steps = [
		[600.0, func(): battle.time_scale_idx = 1, "01_saddle"],
		[601.0, func(): battle._set_telescope(true), "02_telescope_x10"],
		[602.0, func(): battle.player.change_magnification(2.0), "03_telescope_x20"],
		[603.0, func(): battle._open_overlay(battle.map), "04_map"],
		[604.0, func(): battle.map.focus(Vector2(0, 150), 6.0), "05_map_zoomed"],
		[605.0, func(): _open_oob(), "06_oob"],
		[606.0, func(): _show_enemy_oob(), "07_oob_enemy"],
		[607.0, func(): _activate_first_brigade(), "08_oob_to_map"],
	]


## Fold your own army and open the enemy's (only what has been seen).
func _show_enemy_oob() -> void:
	var own: TreeItem = battle.oob.tree.get_root().get_first_child()
	own.collapsed = true
	var it: TreeItem = own.get_next()
	for depth in 4:
		if it == null:
			return
		it.collapsed = false
		it = it.get_first_child()


## As if double-clicking your first brigade: the map opens on it.
func _activate_first_brigade() -> void:
	var it: TreeItem = battle.oob.tree.get_root().get_first_child()
	for depth in 3:
		it = it.get_first_child()
	it.select(0)
	battle.oob._on_activated()


func _open_oob() -> void:
	battle._open_overlay(battle.oob)
	# Unfold the first corps, its first division and that division's first brigade.
	var it: TreeItem = battle.oob.tree.get_root().get_first_child()
	for depth in 4:
		it.collapsed = false
		it = it.get_first_child()


func _process(_delta: float) -> bool:
	if battle.sim == null:
		return false
	frame += 1
	if frame == 2:
		battle.time_scale_idx = battle.TIME_SCALES.size() - 1  # x16 while deploying
	# Keep the real mouse from turning the view during the run.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _shot_in > 0:
		# Let a few frames render before the screenshot.
		_shot_in -= 1
		if _shot_in == 0:
			root.get_viewport().get_texture().get_image().save_png(out.path_join(_shot_name + ".png"))
			print("[ui] %s" % _shot_name)
		return false
	if steps.is_empty():
		return true
	if battle.sim.time >= steps[0][0]:
		var s: Array = steps.pop_front()
		s[1].call()
		_shot_name = s[2]
		_shot_in = 4
	return false
