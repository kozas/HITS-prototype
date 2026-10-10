extends SceneTree
## Headless check of the player command loop: write order -> courier rides ->
## delivered -> staff delay -> battalions execute -> the brigade reports it done.
## Run on Corps command, where everyone is halted out of range, so nothing but
## the order moves the brigade.
##   godot --headless --path hits-prototype --script res://tools/order_test.gd

const Order = preload("res://src/order.gd")

var main
var order
var frames := 0
var seen := {}


func _initialize() -> void:
	root.get_node("GameState").scenario = 2  # CORPS_COMMAND
	main = load("res://battle.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main.time_scale_idx = main.TIME_SCALES.size() - 1
		var b = main.sim.brigades[4]  # 3rd Division's leading brigade, in route column
		var dest: Vector2 = b.centroid() + Vector2(300, 0)
		order = main.issue_player_order(b, dest, 2)  # square, 300 m to the east
		print("t=%.0fs order written for %s, %.0f m from the general" % [main.sim.time, b.label, main.player_xz().distance_to(b.centroid())])
	if frames > 2:
		var st: String = order.status_name()
		if not seen.has(st):
			seen[st] = main.sim.time
			print("t=%.0fs status -> %s" % [main.sim.time, st])
			if order.status == Order.Status.EXECUTING:
				print("  the brigade chose its front: %s" % main.Orientation.describe(order.facing, order.facing_reason))
		if order.status == Order.Status.COMPLETE:
			var b = order.recipient
			var squares := 0
			for f in b.alive():
				if f.ftype == 2:
					squares += 1
			var ok: bool = squares == b.alive().size()
			for f in b.alive():
				print("  %s: %s, morale %.2f, routing %s, target %s, %.0f m from its place" % [f.label, f.TYPE_NAMES[f.ftype], f.morale, f.routing, f.has_target, f.pos.distance_to(f.target_pos)])
			print("t=%.0fs %s reports the order done, %d of %d battalions in square: %s" % [main.sim.time, b.label, squares, b.alive().size(), "PASS" if ok else "FAIL"])
			return true
		if order.status == Order.Status.LOST or order.status == Order.Status.SUPERSEDED:
			print("FAIL: order %s" % st)
			return true
	if main.sim.time > 3600.0 or frames > 200000:
		print("FAIL: order stuck in status %s" % order.status_name())
		for f in order.recipient.alive():
			print("  %s: %s, morale %.2f, routing %s, engaged %s, target %s, %.0f m from its place" % [f.label, f.TYPE_NAMES[f.ftype], f.morale, f.routing, f.engaged, f.has_target, f.pos.distance_to(f.station)])
		return true
	return false
