extends Node3D
## Orders are physical: a rider carries each one across the field. He rides to
## wherever the brigade commander is *now*, can be shot riding past the enemy,
## and the order only takes effect after delivery plus staff time.

const Meshes = preload("res://src/meshes.gd")

const SPEED := 6.5  # m/s, a hard canter over broken ground (~23 km/h)
const HAZARD_RADIUS := 140.0
const HAZARD_PER_SEC := 0.03

var sim
var terrain
var couriers: Array = []
var delivered := 0
var lost := 0
var player_army := 0
## Callable(text: String) for HUD messages.
var notify: Callable
var _meshes := []
var _mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()


class Courier:
	var node: MeshInstance3D
	var pos := Vector2.ZERO
	var home := Vector2.ZERO
	var army := 0
	var order: Dictionary
	var returning := false
	var heading := 0.0
	var hazard_t := 0.0


func setup(s, t) -> void:
	sim = s
	terrain = t
	_meshes = [Meshes.rider(Color(0.1, 0.12, 0.35)), Meshes.rider(Color(0.55, 0.07, 0.06))]
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.85


func dispatch(o: Dictionary, origin: Vector2) -> void:
	var c := Courier.new()
	c.pos = origin
	c.home = origin
	c.army = o.army
	c.order = o
	c.node = MeshInstance3D.new()
	c.node.mesh = _meshes[o.army]
	c.node.material_override = _mat
	c.node.visibility_range_end = 2500.0
	add_child(c.node)
	o.status = "riding"
	sim.brigades[o.brigade].awaiting = true
	couriers.append(c)


func update(dt: float, time: float) -> void:
	for c in couriers.duplicate():
		var target: Vector2 = c.home if c.returning else sim.brigades[c.order.brigade].centroid()
		var to: Vector2 = target - c.pos
		var d: float = to.length()
		var step := SPEED * dt
		if d <= maxf(step, 12.0):
			if c.returning:
				_remove(c)
				continue
			sim.deliver_order(c.order)
			delivered += 1
			c.returning = true
			if c.army == player_army and notify.is_valid():
				notify.call("Order delivered to %s (%s after writing)" % [_brigade_name(c.order), _mmss(time - c.order.issued)])
			continue
		c.pos += to / d * step
		c.heading = atan2(-to.x, -to.y)
		c.hazard_t += dt
		while c.hazard_t >= 1.0:
			c.hazard_t -= 1.0
			if sim.nearest_enemy(c.pos, c.army, HAZARD_RADIUS) != null and rng.randf() < HAZARD_PER_SEC:
				_kill(c)
				break
		if is_instance_valid(c.node):
			var bob := absf(sin(time * 9.0)) * 0.12
			c.node.transform = Transform3D(Basis(Vector3.UP, c.heading), Vector3(c.pos.x, terrain.height(c.pos.x, c.pos.y) + bob, c.pos.y))


func _kill(c: Courier) -> void:
	if not c.returning:
		sim.order_lost(c.order)
		lost += 1
		if c.army == player_army and notify.is_valid():
			notify.call("No word from the courier sent to %s..." % _brigade_name(c.order))
	_remove(c)


func _remove(c: Courier) -> void:
	c.node.queue_free()
	couriers.erase(c)


func riding_count(army: int) -> int:
	var n := 0
	for c in couriers:
		if c.army == army and not c.returning:
			n += 1
	return n


func _brigade_name(o: Dictionary) -> String:
	return sim.brigades[o.brigade].label


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
