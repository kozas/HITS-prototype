extends Node3D
## Draws the riders carrying orders. Couriers live in the sim (BattleSim.Courier,
## stepped at 10 Hz so the battle is the same at any frame rate); this only
## gives each one a horse and keeps it where the sim says, between ticks.

const Meshes = preload("res://src/meshes.gd")

var sim
var terrain
var _meshes := []
var _mat: StandardMaterial3D
var _nodes := {}  # Courier -> MeshInstance3D


func setup(s, t) -> void:
	sim = s
	terrain = t
	_meshes = [Meshes.rider(Color(0.1, 0.12, 0.35)), Meshes.rider(Color(0.55, 0.07, 0.06))]
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.85


func update(alpha: float, time: float) -> void:
	var seen := {}
	for c in sim.couriers:
		seen[c] = true
		var node: MeshInstance3D = _nodes.get(c)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _meshes[c.army]
			node.material_override = _mat
			node.visibility_range_end = 2500.0
			add_child(node)
			_nodes[c] = node
		var p: Vector2 = c.prev_pos.lerp(c.pos, alpha)
		var to: Vector2 = c.pos - c.prev_pos
		var heading: float = atan2(-to.x, -to.y) if to != Vector2.ZERO else node.rotation.y
		var bob := absf(sin(time * 9.0)) * 0.12
		node.transform = Transform3D(Basis(Vector3.UP, heading), Vector3(p.x, terrain.height(p.x, p.y) + bob, p.y))
	if seen.size() != _nodes.size():
		for c in _nodes.keys():
			if not seen.has(c):
				_nodes[c].queue_free()
				_nodes.erase(c)
