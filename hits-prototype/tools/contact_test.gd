extends SceneTree
## Brigade contact: the French brigade is ordered forward to 60 m short of the
## Allied line (who hold their ground). Checks that
## - the battalions keep dressed on one another on the way (no more than
##   12 m between the most forward and the rearmost along the line of advance),
## - the lines come to musketry within 15 minutes.
## Run with a fixed timestep so sim time = frames/60:
##   godot --headless --fixed-fps 60 --path hits-prototype --script res://tools/contact_test.gd

const MAX_SPREAD := 12.0
const DEADLINE := 900.0

var battle
var order
var t_engaged := -1.0
var t_volley := -1.0
var spread := 0.0
var spread_at := 0.0


func _initialize() -> void:
	root.get_node("GameState").scenario = 1  # BRIGADE_CONTACT
	battle = load("res://battle.tscn").instantiate()
	root.add_child(battle)


func _process(_delta: float) -> bool:
	var sim = battle.sim
	if sim == null:
		return false
	if order == null:
		var b = sim.brigades[0]
		var enemy: Vector2 = sim.brigades[1].centroid()
		var dest: Vector2 = b.centroid() + (enemy - b.centroid()).normalized() * (b.centroid().distance_to(enemy) - 60.0 - 20.0)
		order = sim.make_order(b, dest, 0)  # line
		sim._hand_over(order, 0.0)
		print("t=0s %s ordered forward %.0f m, in line" % [b.label, b.centroid().distance_to(dest)])
	_measure_dressing(sim)
	for f in sim.formations:
		if t_engaged < 0.0 and f.engaged:
			t_engaged = sim.time
			print("t=%.1fs first battalion engaged (%s, %s)" % [sim.time, f.label, sim.brigades[f.brigade].label])
		if t_volley < 0.0 and f.last_shot > 0.0:
			t_volley = f.last_shot
			print("t=%.1fs first fire (%s, %s, %s)" % [f.last_shot, f.label, sim.brigades[f.brigade].label, f.FIRE_NAMES[f.fire_now]])
	if sim.time >= maxf(t_volley, 0.0) + 180.0 and t_volley > 0.0 or sim.time > DEADLINE + 1.0:
		var alive := [sim.soldiers_alive(0), sim.soldiers_alive(1)]
		print("t=%.0fs French %d / Allied %d alive, fallen %d" % [sim.time, alive[0], alive[1], battle.corpses.total])
		print("widest spread along the advance: %.1f m (t=%.0fs)" % [spread, spread_at])
		var ok_fire: bool = t_volley > 0.0 and t_volley < DEADLINE
		var ok_dress: bool = spread <= MAX_SPREAD
		print("PASS" if ok_fire and ok_dress else "FAIL:%s%s" % ["" if ok_fire else " no musketry in time", "" if ok_dress else " the line did not keep dressed"])
		return true
	return false


## During the advance (before first contact), while every battalion is marching
## in the same formation: how far ahead of the rearmost is the most forward?
func _measure_dressing(sim) -> void:
	if order.facing == null or t_engaged >= 0.0:
		return
	var fwd := Vector2(-sin(order.facing), -cos(order.facing))
	var lo := INF
	var hi := -INF
	var ft := -1
	for f in sim.brigades[0].alive():
		if not f.has_target or f.engaged or not f.moving or f.is_transitioning(sim.time):
			return
		if ft >= 0 and f.ftype != ft:
			return
		ft = f.ftype
		var r: float = (f.station - f.pos).dot(fwd)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	if hi - lo > spread:
		spread = hi - lo
		spread_at = sim.time
