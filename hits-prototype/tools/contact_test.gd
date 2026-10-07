extends SceneTree
## Brigade contact timing: how long until the lines are in musket range and
## the first volley is fired. Run with a fixed timestep so sim time = frames/60:
##   godot --headless --fixed-fps 60 --path hits-prototype --script res://tools/contact_test.gd

var battle
var t_engaged := -1.0
var t_volley := -1.0


func _initialize() -> void:
	root.get_node("GameState").scenario = 1  # BRIGADE_CONTACT
	battle = load("res://battle.tscn").instantiate()
	root.add_child(battle)


func _process(_delta: float) -> bool:
	var sim = battle.sim
	if sim == null:
		return false
	for f in sim.formations:
		if t_engaged < 0.0 and f.engaged:
			t_engaged = sim.time
			print("t=%.1fs first battalion engaged (%s, %s)" % [sim.time, f.label, sim.brigades[f.brigade].label])
		if t_volley < 0.0 and f.last_volley > 0.0:
			t_volley = f.last_volley
			print("t=%.1fs first volley (%s, %s)" % [f.last_volley, f.label, sim.brigades[f.brigade].label])
	if sim.time >= 180.0:
		var alive := [sim.soldiers_alive(0), sim.soldiers_alive(1)]
		print("t=%.0fs French %d / Allied %d alive, fallen %d" % [sim.time, alive[0], alive[1], battle.corpses.total])
		print("PASS" if t_volley > 0.0 and t_volley < 45.0 else "FAIL: no musketry within 45 s")
		return true
	return false
