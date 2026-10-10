extends SceneTree
## Headless sim profiler: runs the real BattleSim._tick with per-phase timing.
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
	sim.profile = true
	var ticks := 9000
	var t_all := Time.get_ticks_usec()
	for i in ticks:
		sim._tick()
		sim.events.clear()
	var total := Time.get_ticks_usec() - t_all
	print("%d battalions, %d ticks (%.0f sim-minutes): %.3f ms/tick avg -> %.1f ms of CPU per real second at x16" % [
		sim.formations.size(), ticks, ticks * sim.TICK / 60.0, total / 1000.0 / ticks, total / 1000.0 / ticks * 160.0])
	print("alive %d of %d, couriers delivered %d, lost %d" % [sim.soldiers_alive(), sim.formations.size() * 600, sim.couriers_delivered, sim.couriers_lost])
	for k in sim.phase_usec:
		print("  %-22s %.3f ms/tick" % [k, sim.phase_usec[k] / 1000.0 / ticks])
	terrain.free()
	quit()
