extends Node3D
## Every man who falls stays on the field (1:1). Static instances in spatial
## chunks, so far-away chunks are culled by visibility range and frustum.

const CHUNK := 400.0
const PER_CHUNK := 4096

var mesh: Mesh
var mat: ShaderMaterial
var chunks := {}
var total := 0
var rng := RandomNumberGenerator.new()


class Chunk:
	var node: MultiMeshInstance3D
	var mm: MultiMesh
	var count := 0


func setup(m: Mesh) -> void:
	mesh = m
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/corpse.gdshader")


func add(f, n: int, terrain) -> void:
	var fp: Vector2 = f.footprint()
	var coat: Color = f.get_meta("coat", Color(0.3, 0.3, 0.3))
	for k in n:
		var lx := rng.randf_range(-fp.x * 0.5, fp.x * 0.5)
		var lz := rng.randf_range(0.0, minf(fp.y, 3.0))
		var p: Vector2 = f.pos + f.right() * lx + f.back() * lz - f.forward() * rng.randf_range(0.0, 1.5)
		_place(p, coat, terrain)


func _place(p: Vector2, coat: Color, terrain) -> void:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var ch: Chunk = chunks.get(key)
	if ch == null:
		ch = _make_chunk(key)
	var idx := ch.count % PER_CHUNK
	var origin := Vector3(p.x, terrain.height(p.x, p.y) + 0.13, p.y) - ch.node.position
	var lie := Basis(Vector3.RIGHT, -PI * 0.5 if rng.randf() < 0.5 else PI * 0.5)
	ch.mm.set_instance_transform(idx, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * lie, origin))
	ch.mm.set_instance_custom_data(idx, coat)
	ch.count += 1
	ch.mm.visible_instance_count = mini(ch.count, PER_CHUNK)
	total += 1


func _make_chunk(key: Vector2i) -> Chunk:
	var ch := Chunk.new()
	ch.mm = MultiMesh.new()
	ch.mm.transform_format = MultiMesh.TRANSFORM_3D
	ch.mm.use_custom_data = true
	ch.mm.mesh = mesh
	ch.mm.instance_count = PER_CHUNK
	ch.mm.visible_instance_count = 0
	ch.node = MultiMeshInstance3D.new()
	ch.node.multimesh = ch.mm
	ch.node.material_override = mat
	ch.node.position = Vector3((key.x + 0.5) * CHUNK, 0, (key.y + 0.5) * CHUNK)
	ch.node.custom_aabb = AABB(Vector3(-CHUNK * 0.6, -100, -CHUNK * 0.6), Vector3(CHUNK * 1.2, 200, CHUNK * 1.2))
	ch.node.visibility_range_end = 900.0
	ch.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ch.node)
	chunks[key] = ch
	return ch
