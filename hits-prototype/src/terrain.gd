extends Node3D
## Heightmap terrain. One float texture is the single source of truth for the
## terrain mesh, every soldier/flag/ribbon shader, and the CPU sampler below.

const N := 512
const SPACING := 12.0
const SIZE := (N - 1) * SPACING

var heights := PackedFloat32Array()
var heightmap: ImageTexture
var material: ShaderMaterial
var detail_noise: NoiseTexture2D


func generate(seed_value: int) -> void:
	var base := FastNoiseLite.new()
	base.seed = seed_value
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 1.0 / 1400.0
	base.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 7
	detail.frequency = 1.0 / 320.0
	detail.fractal_octaves = 2

	heights.resize(N * N)
	var half := SIZE * 0.5
	for iz in N:
		var z := iz * SPACING - half
		for ix in N:
			var x := ix * SPACING - half
			var h := base.get_noise_2d(x, z) * 38.0 + detail.get_noise_2d(x, z) * 6.0
			# Two low ridges with a shallow valley between: each army starts on one,
			# giving reverse slopes to hide behind (Waterloo-style).
			var az := absf(z)
			h += 16.0 * exp(-pow((az - 900.0) / 400.0, 2.0))
			h -= 8.0 * exp(-pow(z / 420.0, 2.0))
			var edge := maxf(absf(x), az)
			h *= smoothstep(half, half - 700.0, edge)
			heights[iz * N + ix] = h

	var img := Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())
	heightmap = ImageTexture.create_from_image(img)

	detail_noise = NoiseTexture2D.new()
	var dn := FastNoiseLite.new()
	dn.seed = seed_value + 3
	dn.frequency = 0.02
	detail_noise.noise = dn
	detail_noise.seamless = true
	detail_noise.width = 512
	detail_noise.height = 512

	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	apply_height_params(material)
	material.set_shader_parameter("detail_noise", detail_noise)
	material.set_shader_parameter("grid_spacing", SPACING)

	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = N - 2
	plane.subdivide_depth = N - 2
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = material
	mi.custom_aabb = AABB(Vector3(-half, -100, -half), Vector3(SIZE, 200, SIZE))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Flat skirt out to the horizon (heights fade to 0 at the edge).
	var skirt := 80000.0
	for k in 4:
		var m := PlaneMesh.new()
		var s := MeshInstance3D.new()
		var w := (skirt - SIZE) * 0.5
		if k < 2:
			m.size = Vector2(skirt, w)
			s.position = Vector3(0, 0, (half + w * 0.5) * (1 if k == 0 else -1))
		else:
			m.size = Vector2(w, SIZE)
			s.position = Vector3((half + w * 0.5) * (1 if k == 2 else -1), 0, 0)
		s.mesh = m
		s.material_override = material
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)


func apply_height_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("heightmap", heightmap)
	mat.set_shader_parameter("hm_res", float(N))
	mat.set_shader_parameter("terrain_size", SIZE)


## Bilinear sample identical to terrain_h() in the shaders.
func height(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / SPACING, 0.0, N - 1.001)
	var fz := clampf((z + SIZE * 0.5) / SPACING, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + N], heights[i + N + 1], tx)
	return lerpf(a, b, tz)


## Can an eye at `from` see the point `to`? Coarse raymarch against the heightmap.
func line_of_sight(from: Vector3, to: Vector3, steps := 16) -> bool:
	var d := to - from
	for s in range(1, steps):
		var t := float(s) / steps
		var p := from + d * t
		if height(p.x, p.z) > p.y + 0.3:
			return false
	return true
