extends SceneTree
## The battle must depend only on the tick count, never on the frame rate: the
## same ticks reached in 16 ms frames and in 50 ms frames must leave every
## battalion (and courier) in exactly the same state. Needed for time
## compression, replays and fair tests.
##   godot --headless --path hits-prototype --script res://tools/determinism_test.gd

const Terrain = preload("res://src/terrain.gd")
const BattleSim = preload("res://src/battle_sim.gd")

const TICKS := 6000  # 10 sim-minutes: deployment, first couriers, first musketry


func _init() -> void:
	var terrain = Terrain.new()
	terrain.generate(Terrain.MAPS.ridges)
	var a := _run(terrain, 0.016)
	var b := _run(terrain, 0.05)
	print("frame 16 ms: %s" % a)
	print("frame 50 ms: %s" % b)
	print("PASS" if a == b else "FAIL: the battle depends on the frame rate")
	terrain.free()
	quit()


func _run(terrain, frame: float) -> String:
	var sim = BattleSim.new(terrain)
	sim.deploy(160, 600, 450.0)
	sim.ai_enabled = [true, true]
	sim._rebuild_grid()
	while sim.tick_count < TICKS:
		sim.advance(frame)
		sim.events.clear()
	if sim.tick_count != TICKS:
		return "overshot to tick %d" % sim.tick_count
	var state := PackedFloat64Array()
	for f in sim.formations:
		state.append_array([f.pos.x, f.pos.y, f.facing, f.strength, f.morale, f.ftype])
	for c in sim.couriers:
		state.append_array([c.pos.x, c.pos.y])
	return "tick %d, %d men, %d couriers out, %d delivered, state hash %d" % [
		sim.tick_count, sim.soldiers_alive(), sim.couriers.size(), sim.couriers_delivered, hash(state.to_byte_array())]
