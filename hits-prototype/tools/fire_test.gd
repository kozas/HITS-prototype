extends SceneTree
## The three manners of fire, side by side: one battalion in line fires for two
## minutes on another that does not fire back, at 50, 100 and 150 m. Prints
## casualties per minute and morale lost per casualty. Checks that
## - fire falls off with range, for every mode;
## - the three modes kill at much the same rate (within 40% of one another);
## - per casualty, a volley shakes the target most and fire at will least.
##   godot --headless --path hits-prototype --script res://tools/fire_test.gd

const Lab = preload("res://tools/lab.gd")
const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const T := Formation.Type
const F := Formation.Fire

const MODES := [F.VOLLEY, F.PLATOON, F.AT_WILL]
const RANGES := [50.0, 100.0, 150.0]
const MINUTES := 2.0


func _init() -> void:
	var ok := true
	var shock := []
	print("%-12s %s" % ["", "   ".join(RANGES.map(func(r): return "%3d m: cas/min  morale/cas" % r))])
	var per_range := {}
	for mode in MODES:
		var row := []
		var last := INF
		var tot_cas := 0.0
		var tot_morale := 0.0
		for r in RANGES:
			var res := _trial(mode, r)
			row.append("%8.1f  %10.4f" % [res.x, res.y / maxf(res.x * MINUTES, 1.0)])
			ok = ok and res.x < last
			last = res.x
			tot_cas += res.x
			tot_morale += res.y
			per_range[r] = per_range.get(r, []) + [res.x]
		shock.append(tot_morale / maxf(tot_cas * MINUTES, 1.0))
		print("%-12s %s" % [Formation.FIRE_NAMES[mode], "        ".join(row)])
	for r in RANGES:
		var lo: float = per_range[r].min()
		var hi: float = per_range[r].max()
		ok = ok and hi <= lo * 1.4
	ok = ok and shock[0] > shock[1] and shock[1] > shock[2]
	print("morale lost per casualty: volley %.4f, by platoon %.4f, at will %.4f" % shock)
	print("PASS" if ok else "FAIL")
	Lab.free_terrain()
	quit()


## (casualties per minute, morale the target lost) for one mode at one range.
func _trial(mode: int, r: float) -> Vector2:
	var cas := 0.0
	var morale := 0.0
	for s in 4:
		var sim = Lab.new_sim(500 + s)
		var f = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.LINE)
		var e = Lab.battalion(sim, 1, Vector2(0, -r - 3.0), PI, T.LINE)
		Lab.ready(sim)
		var eo = Lab.order(sim, e, Order.Kind.HOLD, Objective.point(e.pos))
		eo.fire_mode = F.HOLD
		var o = Lab.order(sim, f, Order.Kind.HOLD, Objective.point(f.pos))
		o.fire_mode = mode
		var start: int = e.strength
		var lost := 0.0
		var end: float = MINUTES * 60.0
		while sim.time < end:
			var before: float = e.morale
			sim._tick()
			sim.events.clear()
			lost += before - e.morale
			# Keep the target standing so the whole trial measures fire, not rout.
			e.morale = 1.0
		cas += start - e.strength
		morale += lost
	return Vector2(cas / 4.0 / MINUTES, morale / 4.0)
