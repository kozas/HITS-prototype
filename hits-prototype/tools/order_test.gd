extends SceneTree
## Headless check of the player command loop: write order -> courier rides ->
## delivered -> staff delay -> battalions execute.
##   godot --headless --path hits-prototype --script res://tools/order_test.gd

var main
var order: Dictionary
var frames := 0
var seen := {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main.time_scale_idx = main.TIME_SCALES.size() - 1
		var b = main.sim.brigades[2]
		var dest: Vector2 = b.centroid() + Vector2(0, -300)
		main.issue_player_order(b.id, dest, 0.0, 2)  # square, 300 m forward
		order = main.player_orders[-1]
		print("t=%.0fs order written for %s, %.0f m from the general" % [main.sim.time, b.label, main.player_xz().distance_to(b.centroid())])
	if frames > 2:
		var st: String = order.status
		if not seen.has(st):
			seen[st] = main.sim.time
			print("t=%.0fs status -> %s" % [main.sim.time, st])
		if st == "executing":
			var b = main.sim.brigades[order.brigade]
			var squares := 0
			for f in b.alive():
				if f.ftype == 2:
					squares += 1
			if squares == b.alive().size() and not _any_moving(b):
				print("t=%.0fs all %d battalions of %s in square at destination: PASS" % [main.sim.time, squares, b.label])
				return true
	if main.sim.time > 3600.0 or frames > 200000:
		print("FAIL: order stuck in status %s" % order.get("status"))
		return true
	return false


func _any_moving(b) -> bool:
	for f in b.alive():
		if f.has_target:
			return true
	return false
