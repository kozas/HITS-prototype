extends SceneTree
## The battalion's abilities, one case each, on the lab drill ground (headless):
##   godot --headless --path hits-prototype --script res://tools/battalion_test.gd

const Lab = preload("res://tools/lab.gd")
const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const BattalionBrain = preload("res://src/ai/battalion_brain.gd")
const T := Formation.Type
const K := Order.Kind

var failures := 0


func _init() -> void:
	_form_and_face()
	_move()
	_halt_to_fire()
	_all_out_charges()
	_rout_and_rally()
	_at_will_is_slow_to_stop()
	_line_advances_in_line()
	_brigade_advances_in_line()
	_by_the_flank()
	_route_column_far_from_enemy()
	_skirmishers()
	_screen_keeps_station()
	_screen_clears_for_formed_enemy()
	_masked_fire()
	print("PASS" if failures == 0 else "FAIL: %d case(s)" % failures)
	Lab.free_terrain()
	quit()


func _check(name: String, ok: bool, detail: String) -> void:
	print("  %s %s: %s" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		failures += 1


## HOLD where it stands, formation left to it: a column with the enemy off its
## right flank wheels to face him and forms line (French doctrine for holding).
func _form_and_face() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.COLUMN)
	var e = Lab.battalion(sim, 1, Vector2(700, 0), PI * 0.5, T.LINE)
	Lab.ready(sim)
	var o = Lab.order(sim, f, K.HOLD, Objective.point(f.pos))
	o.ftype = T.LINE
	Lab.run(sim, 400.0)
	var off := rad_to_deg(absf(angle_difference(f.facing, Lab.yaw_to(f.pos, e.pos))))
	_check("form and face", f.ftype == T.LINE and off < 10.0 and o.status == Order.Status.EXECUTING,
		"%s, %.0f deg off the enemy, order %s" % [f.TYPE_NAMES[f.ftype], off, o.status_name()])


## MOVE 250 m in column: gets there, forms, reports done.
func _move() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	Lab.ready(sim)
	var dest: Vector2 = f.pos + Vector2(0, 250)
	var o = sim.make_order(f, dest, T.COLUMN, null, f.parent)
	sim._hand_over(o, 0.0)
	Lab.run(sim, 600.0, func(): return o.status == Order.Status.COMPLETE)
	_check("move", o.status == Order.Status.COMPLETE and f.ftype == T.COLUMN,
		"%s at %.0f m from the spot, %s, t=%.0fs" % [o.status_name(), f.pos.distance_to(dest), f.TYPE_NAMES[f.ftype], sim.time])


## ATTACK at PROBE: closes, halts at about 150 m to give fire, never charges.
func _halt_to_fire() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -450), PI, T.LINE)
	Lab.ready(sim)
	Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	var o = Lab.order(sim, f, K.ATTACK, Objective.on_unit(e))
	o.intensity = Order.Intensity.PROBE
	o.ftype = T.LINE
	var closest := INF
	var charged := false
	while sim.time < 600.0:
		sim._tick()
		charged = charged or sim.events.any(func(ev): return ev.type == "charge")
		sim.events.clear()
		closest = minf(closest, f.cpos.distance_to(e.cpos))
	_check("probe halts to fire", f.last_shot > 0.0 and not charged and closest > 110.0 and closest < 185.0,
		"came no closer than %.0f m, fired %s, charged %s" % [closest, f.last_shot > 0.0, charged])


## ATTACK ALL_OUT: goes straight in with the bayonet.
func _all_out_charges() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.COLUMN)
	var e = Lab.battalion(sim, 1, Vector2(0, -400), PI, T.LINE)
	Lab.ready(sim)
	Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	var o = Lab.order(sim, f, K.ATTACK, Objective.on_unit(e))
	o.intensity = Order.Intensity.ALL_OUT
	var evs := Lab.run_events(sim, 600.0)
	var results := evs.filter(func(ev): return ev.type == "charge_result")
	_check("all-out charges", evs.any(func(ev): return ev.type == "charge") and not results.is_empty(),
		"charge result: %s" % (results[0].result if not results.is_empty() else "none"))


## Routed with nobody after it: runs back, rallies, re-forms, and is never
## quite as steady again.
func _rout_and_rally() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	Lab.ready(sim)
	var start: Vector2 = f.pos
	f.morale = 0.2
	sim._start_rout(f)
	var rallied_at := -1.0
	var steady_at := -1.0
	var ran := 0.0
	while sim.time < 600.0 and steady_at < 0.0:
		sim._tick()
		sim.events.clear()
		ran = maxf(ran, f.pos.distance_to(start))
		if rallied_at < 0.0 and f.morale_state == Formation.Morale.RALLYING:
			rallied_at = sim.time
		if rallied_at >= 0.0 and f.is_steady():
			steady_at = sim.time
	_check("rout and rally", steady_at > 0.0 and ran > 50.0 and f.morale <= 0.61,
		"ran %.0f m, rallying at %.0fs, formed again at %.0fs, morale %.2f (cap %.2f)" % [ran, rallied_at, steady_at, f.morale, f.morale_cap])


## Firing at will, the men are slow to stop: an order to move takes 10-20 s.
func _at_will_is_slow_to_stop() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -140), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	var hold = Lab.order(sim, f, K.HOLD, Objective.point(f.pos))
	hold.fire_mode = Formation.Fire.AT_WILL
	Lab.run(sim, 40.0)
	var was_firing: bool = f.firing
	var o = sim.make_order(f, f.pos + Vector2(0, 150), T.LINE, null, f.parent)
	sim._hand_over(o, sim.time)
	var t0: float = sim.time
	var p0: Vector2 = f.pos
	Lab.run(sim, 60.0, func(): return f.pos.distance_to(p0) > 1.0)
	var lag: float = sim.time - t0
	_check("at will is slow to stop", was_firing and lag >= 9.0 and lag < 40.0,
		"firing at will %s, first step after %.0f s" % [was_firing, lag])


## Skirmishers out: the light company leaves as its own unit; recalled, it
## comes back with its survivors, and no man is lost or gained on the way.
func _skirmishers() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	Lab.ready(sim)
	var before: int = f.strength
	sim.set_skirmishers(f, true)
	Lab.run(sim, 180.0)
	var s = f.skirmishers
	var out_ok: bool = s != null and not s.dead and f.company_absent(0) and f.strength + s.strength == before
	sim.set_skirmishers(f, false)
	Lab.run(sim, 300.0, func(): return f.skirmishers == null)
	var back_ok: bool = f.skirmishers == null and not f.company_absent(0) and f.strength == before
	_check("skirmishers out and in", out_ok and back_ok,
		"out %s, back %s, strength %d -> %d" % [out_ok, back_ok, before, f.strength])


# ---------------------------------------------------------------- marching

## A record of every formation a battalion takes while `run` lasts.
func _formations_taken(sim, units: Array, seconds: float, until: Callable) -> Dictionary:
	var seen := {}
	var end: float = sim.time + seconds
	while sim.time < end:
		sim._tick()
		sim.events.clear()
		for f in units:
			seen[f.ftype] = true
		if until.call():
			break
	return seen


## A line in contact ordered 300 m straight ahead advances in line: no column
## at any point, the front kept, and it arrives.
func _line_advances_in_line() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -900), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	var dest: Vector2 = f.pos + Vector2(0, -300)
	var o = sim.make_order(f, dest, T.LINE, null, f.parent)
	sim._hand_over(o, 0.0)
	var max_turn := 0.0
	var seen := {}
	while sim.time < 600.0 and o.status != Order.Status.COMPLETE:
		sim._tick()
		sim.events.clear()
		seen[f.ftype] = true
		max_turn = maxf(max_turn, rad_to_deg(absf(angle_difference(f.facing, 0.0))))
	_check("line advances in line", seen.keys() == [T.LINE] and o.status == Order.Status.COMPLETE and max_turn < 15.0,
		"formations %s, turned up to %.0f deg, %s at %.0f m, t=%.0fs" % [seen.keys().map(func(t): return f.TYPE_NAMES[t]), max_turn, o.status_name(), f.pos.distance_to(dest), sim.time])


## A whole brigade in line, 300 m forward: every battalion stays in line.
func _brigade_advances_in_line() -> void:
	var sim = Lab.new_sim()
	var b = Lab.brigade(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -1000), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	var o = sim.make_order(b, b.centroid() + Vector2(0, -300), T.LINE, null, b.parent)
	sim._hand_over(o, 0.0)
	var seen := _formations_taken(sim, b.battalions, 900.0, func(): return o.status == Order.Status.COMPLETE)
	_check("brigade advances in line", seen.keys() == [T.LINE] and o.status == Order.Status.COMPLETE,
		"formations %s, marched %s, order %s, t=%.0fs" % [seen.keys().map(func(t): return Formation.TYPE_NAMES[t]), Formation.TYPE_NAMES[o.march_ftype], o.status_name(), sim.time])


## A line shifting 100 m to its right goes by the flank: front kept, men faced
## to the right while marching, at the quick step.
func _by_the_flank() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	Lab.ready(sim)
	var dest: Vector2 = f.pos + f.right() * 100.0
	var o = sim.make_order(f, dest, T.LINE, 0.0, f.parent)
	sim._hand_over(o, 0.0)
	var faced := false
	var max_turn := 0.0
	var t0: float = sim.time
	while sim.time < 400.0 and o.status != Order.Status.COMPLETE:
		sim._tick()
		sim.events.clear()
		faced = faced or (f.moving and absf(absf(f.march_dir) - PI * 0.5) < 0.01)
		max_turn = maxf(max_turn, rad_to_deg(absf(angle_difference(f.facing, 0.0))))
	var took: float = sim.time - t0
	_check("by the flank", o.status == Order.Status.COMPLETE and faced and max_turn < 2.0 and took < 100.0 / Formation.ORDINARY_STEP,
		"%s in %.0f s, men faced to the flank %s, front turned %.1f deg" % [o.status_name(), took, faced, max_turn])


## Far from any enemy, a long march goes in route column.
func _route_column_far_from_enemy() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	Lab.ready(sim)
	var o = sim.make_order(f, f.pos + Vector2(0, 1200), T.LINE, null, f.parent)
	sim._hand_over(o, 0.0)
	var seen := _formations_taken(sim, [f], 120.0, func(): return false)
	_check("route column far from the enemy", seen.has(T.MARCH) and f.march_ftype == T.MARCH,
		"marching in %s" % Formation.TYPE_NAMES[f.march_ftype])


# ---------------------------------------------------------------- the screen

## The screen settles parallel to its battalion's front at about 150 m, as wide
## as the battalion; when the battalion then advances in line it stays ahead.
func _screen_keeps_station() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -1100), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	eo.skirmishers = 0
	sim.set_skirmishers(f, true)
	Lab.run(sim, 200.0)
	var s = f.skirmishers
	if s == null:
		_check("screen keeps station", false, "no skirmishers")
		return
	var ahead: float = (s.pos - f.pos).dot(f.forward())
	var skew := rad_to_deg(absf(angle_difference(s.facing, f.facing)))
	var width: float = s.footprint().x / f.footprint_as(T.LINE).x
	var settled: bool = ahead > 120.0 and ahead < 180.0 and skew < 10.0 and width > 0.8 and width < 1.2
	var o = sim.make_order(f, f.pos + f.forward() * 200.0, T.LINE, null, f.parent)
	sim._hand_over(o, sim.time)
	var lo := INF
	while sim.time < 800.0 and o.status != Order.Status.COMPLETE and f.skirmishers != null:
		sim._tick()
		sim.events.clear()
		lo = minf(lo, (s.pos - f.pos).dot(f.forward()))
	var kept: bool = f.skirmishers == s and lo >= BattalionBrain.SCREEN_MIN and o.status == Order.Status.COMPLETE
	_check("screen keeps station", settled and kept,
		"settled %.0f m ahead, %.0f deg off, %.2f of the front; during the advance never nearer than %.0f m, still out %s" % [ahead, skew, width, lo, f.skirmishers == s])


## Formed enemy coming within 120 m of the screen sends it back to rejoin.
func _screen_clears_for_formed_enemy() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -1100), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	eo.skirmishers = 0
	sim.set_skirmishers(f, true)
	Lab.run(sim, 200.0)
	var before: int = f.strength + (f.skirmishers.strength if f.skirmishers else 0)
	# The enemy line comes up to 100 m from the screen.
	e.pos = f.pos + f.forward() * (BattalionBrain.SCREEN_DEPTH + 100.0)
	e.prev_pos = e.pos
	sim._rebuild_grid()
	Lab.run(sim, 300.0, func(): return f.skirmishers == null)
	_check("screen clears for formed enemy", f.skirmishers == null and f.strength == before,
		"rejoined %s, strength %d of %d" % [f.skirmishers == null, f.strength, before])


## Its own skirmishers in front of it: the battalion holds its fire. With them
## out of the way it fires.
func _masked_fire() -> void:
	var sim = Lab.new_sim()
	var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
	var e = Lab.battalion(sim, 1, Vector2(0, -160), PI, T.LINE)
	Lab.ready(sim)
	var eo = Lab.order(sim, e, K.HOLD, Objective.point(e.pos))
	eo.fire_mode = Formation.Fire.HOLD
	eo.skirmishers = 0
	var o = Lab.order(sim, f, K.HOLD, Objective.point(f.pos))
	o.skirmishers = 0
	o.fire_mode = Formation.Fire.VOLLEY
	sim.set_skirmishers(f, true)
	var s = f.skirmishers
	# Pin the screen halfway between the lines for 30 s.
	var held := true
	for i in 300:
		if s != null and not s.dead:
			s.pos = f.pos + f.forward() * 70.0
			s.prev_pos = s.pos
			s.recalled = false
			s.has_target = false
		sim._tick()
		sim.events.clear()
		held = held and f.last_shot < 0.0
	# Now let them go: they rejoin (the enemy is close) and the line opens fire.
	Lab.run(sim, 120.0, func(): return f.last_shot > 0.0)
	_check("masked fire", held and f.last_shot > 0.0,
		"held fire while masked %s, fired once clear %s (t=%.0fs)" % [held, f.last_shot > 0.0, f.last_shot])