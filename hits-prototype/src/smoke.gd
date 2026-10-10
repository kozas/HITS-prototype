extends MultiMeshInstance3D
## Ring buffer of stateless smoke and dust puffs. A puff is written once at
## spawn; smoke.gdshader animates it from its age. Live puffs cost no CPU.

const Formation = preload("res://src/formation.gd")
const T := Formation.Type
const CAP := 16384

var mat: ShaderMaterial
var cursor := 0
var spawned := 0
var rng := RandomNumberGenerator.new()


func setup() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = CAP
	var buf := PackedFloat32Array()
	buf.resize(CAP * 16)
	for i in CAP:
		var o := i * 16
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
		buf[o + 12] = -1.0e6
	mm.buffer = buf
	multimesh = mm

	var noise := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	noise.noise = fn
	noise.seamless = true
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/smoke.gdshader")
	mat.set_shader_parameter("noise_tex", noise)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-4500, -100, -4500), Vector3(9000, 500, 9000))


func spawn(pos: Vector3, t: float, scale: float, kind: int) -> void:
	multimesh.set_instance_transform(cursor, Transform3D(Basis.IDENTITY, pos))
	multimesh.set_instance_custom_data(cursor, Color(t, scale, rng.randf(), float(kind)))
	cursor = (cursor + 1) % CAP
	spawned += 1


func live_estimate() -> int:
	return mini(spawned, CAP)


## A bank of powder smoke along the firing face(s) of the battalion.
func on_volley(f, t: float, terrain) -> void:
	var fp: Vector2 = f.footprint()
	var fwd: Vector2 = f.forward()
	var rt: Vector2 = f.right()
	var points := []
	match f.ftype:
		T.LINE:
			var count := clampi(int(fp.x / 9.0), 2, 24)
			for j in count:
				points.append(f.pos + rt * lerpf(-fp.x * 0.5, fp.x * 0.5, (j + 0.5) / count) + fwd * 2.5)
		T.SQUARE:
			var c: Vector2 = f.pos + f.back() * fp.y * 0.5
			for face in 4:
				var dir := fwd.rotated(face * PI * 0.5)
				var side := dir.orthogonal()
				for j in 3:
					points.append(c + dir * (fp.x * 0.5 + 2.0) + side * (j - 1) * fp.x * 0.3)
		_:
			for j in 3:
				points.append(f.pos + rt * (j - 1) * fp.x * 0.35 + fwd * 2.5)
	for p in points:
		spawn(Vector3(p.x, terrain.height(p.x, p.y) + 1.3, p.y), t + rng.randf() * 0.35, rng.randf_range(0.8, 1.25), 0)


## Continuous fire: a company's discharge (k >= 0, by platoon) or a second of
## fire at will (k = -1, scattered along the front). Smoke stays in proportion
## to rounds fired: over a cycle, as much as one volley makes.
func on_fire(f, k: int, t: float, terrain) -> void:
	var fp: Vector2 = f.footprint()
	var fwd: Vector2 = f.forward()
	var rt: Vector2 = f.right()
	var volley_puffs := clampi(int(fp.x / 9.0), 2, 24) if f.ftype == T.LINE else 3
	var n: int
	var x0 := -0.5
	var x1 := 0.5
	if k >= 0:
		n = maxi(1, roundi(float(volley_puffs) / f.companies))
		if f.ftype == T.LINE:
			x0 = -0.5 + float(k) / f.companies
			x1 = x0 + 1.0 / f.companies
	else:
		n = 1 if rng.randf() < float(volley_puffs) / Formation.AT_WILL_CYCLE - floorf(float(volley_puffs) / Formation.AT_WILL_CYCLE) else 0
		n += int(float(volley_puffs) / Formation.AT_WILL_CYCLE)
	var origin: Vector2 = f.pos
	if f.ftype == T.SQUARE:
		# Whichever face is firing: pick one.
		var dir := fwd.rotated(rng.randi_range(0, 3) * PI * 0.5)
		fwd = dir
		rt = dir.orthogonal()
		origin = f.pos + f.back() * fp.y * 0.5 + dir * fp.y * 0.5
	for j in n:
		var p: Vector2 = origin + rt * fp.x * rng.randf_range(x0, x1) + fwd * 2.5
		spawn(Vector3(p.x, terrain.height(p.x, p.y) + 1.3, p.y), t + rng.randf() * (0.35 if k >= 0 else 1.0), rng.randf_range(0.7, 1.1), 0)


## Marching columns kick up dust that can be seen over ridges.
func update_dust(formations: Array, t: float, terrain) -> void:
	for f in formations:
		if f.dead or not f.moving or f.routing or not (f.ftype == T.COLUMN or f.ftype == T.MARCH):
			continue
		if rng.randf() < 0.4:
			var p: Vector2 = f.cpos + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15))
			spawn(Vector3(p.x, terrain.height(p.x, p.y) + 0.5, p.y), t, rng.randf_range(0.7, 1.1), 1)
