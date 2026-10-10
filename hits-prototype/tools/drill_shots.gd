extends SceneTree
## Drill review: one battalion is put through line -> column -> square -> march ->
## line while a camera watches, with screenshots mid-manoeuvre and after each.
## Needs a window (no --headless):
##   godot --path hits-prototype --resolution 1600x900 --script res://tools/drill_shots.gd -- --out=DIR [--bn=N]
## Battalions 0-3 are French (6 companies, 3 ranks), 4-7 British (10 companies, 2 ranks).

const T := preload("res://src/formation.gd").Type
const SEQUENCE := [T.COLUMN, T.SQUARE, T.MARCH, T.LINE]

var battle
var f
var out := "."
var bn := 1
var step := -1
var shots := []  # pending [sim_time, name]
var next_order := 4.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--bn="):
			bn = int(a.get_slice("=", 1))
	root.get_node("GameState").scenario = 1  # BRIGADE_CONTACT
	battle = load("res://battle.tscn").instantiate()
	root.add_child(battle)


func _process(_delta: float) -> bool:
	if battle.sim == null:
		return false
	var sim = battle.sim
	if f == null:
		sim.brigades[0].inbox.clear()  # hold the brigade in place
		f = sim.formations[bn]
		battle.hud.visible = false
		battle.time_scale_idx = 3  # x4
		battle._set_free_cam(true)
		shots = [[2.0, "00_line_front"], [2.5, "00_line_close"], [2.8, "00_line_flank"], [3.0, "01_line_rear"]]
	_frame_camera(sim.time)
	if not shots.is_empty() and sim.time >= shots[0][0]:
		var s: Array = shots.pop_front()
		root.get_viewport().get_texture().get_image().save_png(out.path_join(s[1] + ".png"))
		print("[drill] t=%.0fs %s  pos=%s moving=%s target=%s" % [sim.time, s[1], f.pos, f.moving, f.has_target])
	if shots.is_empty() and sim.time >= next_order:
		step += 1
		if step == SEQUENCE.size():
			# Finally advance in line: the guides généraux step out 6 paces ahead.
			f.target_pos = f.pos + f.forward() * 80.0
			f.target_facing = f.facing
			f.target_ftype = f.ftype
			f.march_ftype = f.ftype
			f.has_target = true
			shots = [[sim.time + 8.0, "10_advance"], [sim.time + 8.5, "10_advance_close"], [sim.time + 9.0, "10_advance_flank"]]
			next_order = sim.time + 9.0
			return false
		if step > SEQUENCE.size():
			return true
		f.begin_transition(SEQUENCE[step], sim.time)
		var name: String = ["column", "square", "march", "line"][step]
		print("[drill] t=%.0fs order: form %s (%.0f s)" % [sim.time, name, f.trans_dur])
		var end: float = sim.time + f.trans_dur + 2.0
		shots = [[sim.time + f.trans_dur * 0.4, "%02d_to_%s_mid" % [step * 2 + 2, name]], [end, "%02d_%s" % [step * 2 + 3, name]], [end + 0.5, "%02d_%s_top" % [step * 2 + 3, name]], [end + 1.0, "%02d_%s_close" % [step * 2 + 3, name]]]
		next_order = sim.time + f.trans_dur + 3.0
	return false


## Oblique view from in front and to the right; from behind for the rear shot.
func _frame_camera(t: float) -> void:
	var shot_name: String = shots[0][1] if not shots.is_empty() else ""
	var depth: float = f.footprint().y
	if shot_name.ends_with("_top"):
		# Straight down, front of the battalion at the top of the frame.
		var c: Vector2 = f.pos - f.forward() * depth * 0.5
		battle.free_cam.place(Vector3(c.x, battle.terrain.height(c.x, c.y) + 120.0, c.y), f.facing, -PI * 0.5 + 0.001)
		return
	if shot_name.ends_with("_flank"):
		# Off the right flank, level with the front rank.
		var edge: Vector2 = f.pos + f.right() * f.footprint().x * 0.5
		var c3: Vector2 = edge + f.right() * 14.0 + f.forward() * 3.0
		var l3: Vector2 = edge - f.right() * 6.0 - c3
		battle.free_cam.place(Vector3(c3.x, battle.terrain.height(c3.x, c3.y) + 2.5, c3.y), atan2(-l3.x, -l3.y), -0.08)
		return
	if shot_name.ends_with("_close"):
		# Low and close, off the right front, looking along the front rank.
		var t2: Vector2 = f.pos + f.right() * f.footprint().x * 0.2 - f.forward() * depth * 0.3
		var c2: Vector2 = t2 + f.forward() * 13.0 + f.right() * 9.0
		var l2: Vector2 = t2 - c2
		battle.free_cam.place(Vector3(c2.x, battle.terrain.height(c2.x, c2.y) + 4.0, c2.y), atan2(-l2.x, -l2.y), -0.18)
		return
	var rear := shot_name.ends_with("rear")
	var fwd: Vector2 = f.forward() * (-45.0 if rear else 30.0)
	var cam: Vector2 = f.pos + fwd + f.right() * 40.0 - f.forward() * depth * 0.5
	var look: Vector2 = f.pos - f.forward() * depth * 0.5 - cam
	var h: float = battle.terrain.height(cam.x, cam.y) + 14.0
	var yaw := atan2(-look.x, -look.y)
	var pitch := -atan2(14.0, look.length())
	battle.free_cam.place(Vector3(cam.x, h, cam.y), yaw, pitch)
