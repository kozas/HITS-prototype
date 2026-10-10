extends SceneTree
## The battalion's abilities, one case each, on the lab drill ground (headless):
##   godot --headless --path hits-prototype --script res://tools/battalion_test.gd

const Lab = preload("res://tools/lab.gd")
const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
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
	_skirmishers()
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
	Lab.run(sim, 120.0)
	var s = f.skirmishers
	var out_ok: bool = s != null and not s.dead and f.company_absent(0) and f.strength + s.strength == before
	var ahead := 0.0
	if s != null:
		ahead = (s.pos - f.pos).dot(f.forward())
	sim.set_skirmishers(f, false)
	Lab.run(sim, 300.0, func(): return f.skirmishers == null)
	var back_ok: bool = f.skirmishers == null and not f.company_absent(0) and f.strength == before
	_check("skirmishers", out_ok and back_ok and ahead > 60.0,
		"out %s (%.0f m ahead), back %s, strength %d -> %d" % [out_ok, ahead, back_ok, before, f.strength])
