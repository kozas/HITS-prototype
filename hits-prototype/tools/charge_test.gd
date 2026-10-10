extends SceneTree
## Bayonet charges over many seeds: a French column sent in at the pas de charge
## from 150 m against a British line holding its ground. Most charges were
## decided before the bayonets crossed, by nerve and by the closing volley:
## - a steady line should stop the column more often than not;
## - a shaken line should break before it more often than not.
##   godot --headless --path hits-prototype --script res://tools/charge_test.gd

const Lab = preload("res://tools/lab.gd")
const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const T := Formation.Type

const SEEDS := 50


func _init() -> void:
	var steady := _series(1.0)
	var shaken := _series(0.45)
	var stopped: int = steady.get("faltered", 0) + steady.get("recoiled", 0) + steady.get("repulsed", 0)
	var broke: int = shaken.get("broke", 0) + shaken.get("won", 0)
	print("steady line: %s -> stopped %d%%" % [steady, stopped * 100 / SEEDS])
	print("shaken line: %s -> broke %d%%" % [shaken, broke * 100 / SEEDS])
	var ok: bool = stopped * 2 > SEEDS and broke * 10 > SEEDS * 6
	print("PASS" if ok else "FAIL: steady should stop > 50%, shaken should break > 60%")
	Lab.free_terrain()
	quit()


## Outcome counts over SEEDS charges against a defender with this morale.
func _series(defender_morale: float) -> Dictionary:
	var out := {}
	for s in SEEDS:
		var sim = Lab.new_sim(1000 + s)
		var a = Lab.battalion(sim, 0, Vector2.ZERO, 0.0, T.COLUMN)
		var d = Lab.battalion(sim, 1, Vector2(0, -170), PI, T.LINE)
		Lab.ready(sim)
		Lab.order(sim, d, Order.Kind.HOLD, Objective.point(d.pos))
		d.morale = defender_morale
		d.set_morale_state(Formation.Morale.SHAKEN if defender_morale < 0.45 + 0.01 else Formation.Morale.STEADY, 0.0)
		d.last_shot = -1000.0
		var o = Lab.order(sim, a, Order.Kind.ATTACK, Objective.on_unit(d))
		o.intensity = Order.Intensity.ALL_OUT
		var result := "none"
		while sim.time < 300.0 and result == "none":
			sim._tick()
			for ev in sim.events:
				if ev.type == "charge_result":
					result = ev.result
			sim.events.clear()
		out[result] = out.get(result, 0) + 1
	return out
