extends SceneTree
## Headless sim profiler (mirrors BattleSim._tick's schedule):
##   godot --headless --path hits-prototype --script res://tools/sim_profile.gd

const Terrain = preload("res://src/terrain.gd")
const BattleSim = preload("res://src/battle_sim.gd")


func _init() -> void:
	var terrain = Terrain.new()
	terrain.generate(Terrain.MAPS.ridges)
	var sim = BattleSim.new(terrain)
	sim.deploy(160, 600, 450.0)
	sim.ai_enabled = [true, true]
	sim._rebuild_grid()
	var phases := {"orders+hits": 0, "move": 0, "grid (2 Hz)": 0, "separate (1 Hz)": 0, "slopes (1 Hz)": 0, "combat (1 Hz)": 0, "ai (1 Hz)": 0}
	var ticks := 9000
	var t_all := Time.get_ticks_usec()
	for i in ticks:
		sim.time += sim.TICK
		sim.tick_count += 1
		var t := Time.get_ticks_usec()
		sim._process_orders()
		sim._apply_hits()
		phases["orders+hits"] += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		for f in sim.formations:
			sim._move(f, sim.TICK)
		phases["move"] += Time.get_ticks_usec() - t
		if sim.tick_count % 5 == 0:
			t = Time.get_ticks_usec()
			sim._rebuild_grid()
			phases["grid (2 Hz)"] += Time.get_ticks_usec() - t
		if sim.tick_count % 10 == 0:
			t = Time.get_ticks_usec()
			sim._separate()
			phases["separate (1 Hz)"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			sim._update_slopes()
			phases["slopes (1 Hz)"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			sim._combat(1.0)
			phases["combat (1 Hz)"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			sim._ai()
			phases["ai (1 Hz)"] += Time.get_ticks_usec() - t
		sim.events.clear()
	var total := Time.get_ticks_usec() - t_all
	print("%d battalions, %d ticks (%.0f sim-minutes): %.3f ms/tick avg -> %.1f ms of CPU per real second at x16" % [
		sim.formations.size(), ticks, ticks * sim.TICK / 60.0, total / 1000.0 / ticks, total / 1000.0 / ticks * 160.0])
	print("alive %d of %d" % [sim.soldiers_alive(), sim.formations.size() * 600])
	for k in phases:
		print("  %-16s %.3f ms/tick" % [k, phases[k] / 1000.0 / ticks])
	quit()
