extends SceneTree
## Visual review of the battalion's new drill on Brigade contact. Needs a window:
##   godot --path hits-prototype --resolution 1600x900 --script res://tools/fire_shots.gd -- --out=DIR [--part=fire|skirmish|march]
## fire: the French line is moved up to 130 m from the Allied line; its four
##   battalions fire by volley, by platoon, at will and by volley, while the
##   British reply (an opening volley, then by platoons). Then the right-hand
##   French battalion charges.
## skirmish: both brigades throw out their light companies at 600 m: the chain
##   running out, the screen established; then the French brigade advances
##   200 m in line and its screen moves up ahead of it.
## march: the ways a line moves: by the flank (men faced right), stepping back
##   (faced about) and advancing, all keeping their front.

const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const F := Formation.Fire

var battle
var out := "."
var part := "fire"
var shots: Array = []  # [sim time, name, Callable(camera)]
var _ready := false
var _shot_in := 0
var _shot_name := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--part="):
			part = a.get_slice("=", 1)
	root.get_node("GameState").scenario = 1  # BRIGADE_CONTACT
	battle = load("res://battle.tscn").instantiate()
	root.add_child(battle)


func _process(_d: float) -> bool:
	if battle.sim == null:
		return false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sim = battle.sim
	if not _ready:
		_ready = true
		battle.hud.visible = false
		battle._set_free_cam(true)
		battle.time_scale_idx = 1
		if part == "fire":
			_setup_fire(sim)
		elif part == "march":
			_setup_march(sim)
		else:
			_setup_skirmish(sim)
	if _shot_in > 0:
		_shot_in -= 1
		if _shot_in == 0:
			root.get_viewport().get_texture().get_image().save_png(out.path_join(_shot_name + ".png"))
			print("[shot] t=%.1f %s" % [sim.time, _shot_name])
		return false
	if shots.is_empty():
		return true
	if sim.time >= shots[0][0]:
		var s: Array = shots.pop_front()
		s[2].call()
		_shot_name = s[1]
		_shot_in = 3
	return false


func _french(sim) -> Array:
	return sim.brigades[0].battalions


func _british(sim) -> Array:
	return sim.brigades[1].battalions


func _setup_fire(sim) -> void:
	var gap := 130.0
	var fr: Array = _french(sim)
	var br: Array = _british(sim)
	var shift: float = fr[0].pos.y - br[0].pos.y - gap
	for f in fr:
		f.pos.y -= shift
		f.prev_pos = f.pos
		f.cpos = f.center()
	sim._rebuild_grid()
	var modes := [F.VOLLEY, F.PLATOON, F.AT_WILL, F.VOLLEY]
	for k in fr.size():
		var o = sim.new_order(fr[k], Order.Kind.HOLD, Objective.point(fr[k].pos))
		o.fire_mode = modes[k]
		o.skirmishers = 0
		sim._hand_over(o, 0.0)
	var mid: Vector2 = (fr[1].pos + br[1].pos) * 0.5
	shots = [
		[4.0, "00_lines", func(): _cam_over(mid + Vector2(260, 40), mid, 60.0)],
		[16.0, "01_french_volley_platoon", func(): _cam_along(fr[1], fr[0], 0.0)],
		[20.0, "02_french_platoon_at_will", func(): _cam_along(fr[1], fr[2], 0.0)],
		[24.0, "03_british_reply", func(): _cam_along(br[1], br[2], 0.0)],
		[30.0, "04_french_at_will_close", func(): _cam_close(fr[2])],
		[34.0, "05_french_platoon_close", func(): _cam_close(fr[1])],
		[40.0, "06_smoke_overview", func(): _cam_over(mid + Vector2(300, 120), mid, 90.0)],
		[45.0, "07_charge_ordered", func(): _charge(sim, fr[3], br[3])],
		[75.0, "08_charge_going_in", func(): _cam_over(fr[3].pos + Vector2(180, 60), fr[3].pos + Vector2(0, -60), 45.0)],
		[95.0, "09_charge_result", func(): _cam_over(fr[3].pos + Vector2(200, 80), fr[3].pos + Vector2(0, -60), 60.0)],
		[140.0, "10_after", func(): _cam_over(mid + Vector2(320, 140), mid, 110.0)],
	]


func _charge(sim, f, target) -> void:
	var o = sim.new_order(f, Order.Kind.ATTACK, Objective.on_unit(target))
	o.intensity = Order.Intensity.ALL_OUT
	sim._hand_over(o, sim.time)
	_cam_over(f.pos + Vector2(160, 70), f.pos + Vector2(0, -60), 40.0)


func _setup_skirmish(sim) -> void:
	# From the brigadier, so the battalions stay his to move later.
	for f in _french(sim):
		var o = sim.new_order(f, Order.Kind.HOLD, Objective.point(f.pos), sim.brigades[0])
		o.skirmishers = 1
		o.facing = f.facing
		sim._hand_over(o, 0.0)
	var fr: Array = _french(sim)
	var br: Array = _british(sim)
	var mid: Vector2 = (fr[1].pos + br[1].pos) * 0.5
	battle.time_scale_idx = 3  # x4: it is a long run out
	shots = [
		[6.0, "00_running_out", func(): _cam_close(fr[1])],
		[10.0, "01_running_out_wide", func(): _cam_over(fr[1].pos + Vector2(150, 90), fr[1].pos + Vector2(0, -60), 40.0)],
		[170.0, "02_screen_out", func(): _cam_over(fr[1].pos + Vector2(240, 60), fr[1].pos + Vector2(0, -150), 50.0)],
		[175.0, "03_screen_close", func(): _cam_close(fr[1].skirmishers if fr[1].skirmishers else fr[1])],
		[180.0, "04_both_screens", func(): _cam_over(mid + Vector2(420, 120), mid, 140.0)],
		[200.0, "05_top_down", func(): _top(mid, 520.0)],
		[205.0, "06_advance_ordered", func(): _advance(sim, 200.0)],
		[300.0, "07_advancing_top", func(): _top(mid, 520.0)],
		[330.0, "08_advancing_screen", func(): _cam_over(fr[1].pos + Vector2(220, 40), fr[1].pos + Vector2(0, -120), 45.0)],
		[460.0, "09_arrived_top", func(): _top(mid, 520.0)],
	]


func _advance(sim, metres: float) -> void:
	var b = sim.brigades[0]
	var o = sim.make_order(b, b.centroid() + Vector2(0, -metres), Formation.Type.LINE)
	o.skirmishers = 1
	sim._hand_over(o, sim.time)
	_top((_french(sim)[1].pos + _british(sim)[1].pos) * 0.5, 520.0)


func _setup_march(sim) -> void:
	var fr: Array = _french(sim)
	var moves := [fr[0].right() * 100.0, fr[1].back() * 120.0, fr[2].forward() * 150.0, fr[3].forward() * 150.0]
	for k in fr.size():
		var o = sim.make_order(fr[k], fr[k].pos + moves[k], Formation.Type.LINE, fr[k].facing, sim.brigades[0])
		o.skirmishers = 0
		sim._hand_over(o, 0.0)
	shots = [
		[25.0, "00_by_the_flank", func(): _cam_close(fr[0])],
		[27.0, "01_by_the_flank_side", func(): _cam_side(fr[0])],
		[30.0, "02_stepping_back", func(): _cam_close(fr[1])],
		[33.0, "03_advancing", func(): _cam_close(fr[2])],
		[36.0, "04_top", func(): _top(fr[1].pos + Vector2(0, -40), 260.0)],
		[200.0, "05_halted_fronted", func(): _cam_close(fr[1])],
	]


## Level with a battalion's right-hand file, a few paces off its right flank,
## looking back along the front: a battalion marching by the right flank comes
## towards the camera, the men showing their faces.
func _cam_side(f) -> void:
	var c: Vector2 = f.pos + f.right() * (f.footprint().x * 0.5 + 8.0) + f.back() * 1.0
	var l: Vector2 = f.pos + f.back() * 1.0 - c
	battle.free_cam.place(Vector3(c.x, battle.terrain.height(c.x, c.y) + 1.8, c.y), atan2(-l.x, -l.y), -0.05)


func _top(at: Vector2, h: float) -> void:
	battle.free_cam.place(Vector3(at.x, battle.terrain.height(at.x, at.y) + h, at.y), 0.0, -PI * 0.5 + 0.001)


## Low behind a battalion's line, looking along it towards another.
func _cam_along(f, towards, _h: float) -> void:
	var p: Vector2 = f.pos + f.back() * 12.0 + (f.pos - towards.pos).normalized() * 30.0
	var look: Vector2 = towards.pos + f.forward() * 20.0 - p
	battle.free_cam.place(Vector3(p.x, battle.terrain.height(p.x, p.y) + 6.0, p.y), atan2(-look.x, -look.y), -0.12)


## Close and low off the right front of a formation.
func _cam_close(f) -> void:
	var t: Vector2 = f.pos + f.right() * f.footprint().x * 0.15
	var c: Vector2 = t + f.forward() * 22.0 + f.right() * 18.0
	var l: Vector2 = t - c
	battle.free_cam.place(Vector3(c.x, battle.terrain.height(c.x, c.y) + 5.0, c.y), atan2(-l.x, -l.y), -0.15)


func _cam_over(at: Vector2, look_at: Vector2, h: float) -> void:
	var l: Vector2 = look_at - at
	battle.free_cam.place(Vector3(at.x, battle.terrain.height(at.x, at.y) + h, at.y), atan2(-l.x, -l.y), -atan2(h, l.length()))
