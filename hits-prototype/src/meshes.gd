extends RefCounted
## Procedural low-poly meshes. Vertex data carries animation metadata for the
## soldier shader:
##   UV.x  = material slot (0 vertex colour, 1 coat, 2 trim, 3 trousers)
##   UV.y  = part (0 static, 1 left leg, 2 right leg, 3 musket, 4 far card, 5 muzzle flash)
##   UV2   = rotation pivot (y, z) for animated parts

const HIP := Vector2(0.86, 0.0)
const SHOULDER := Vector2(1.38, 0.0)

# Box faces as (normal, u, v) with u x v = normal.
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]


static func lin(r: float, g: float, b: float) -> Color:
	return Color(r, g, b).srgb_to_linear()


## Godot front faces are clockwise, so each quad is emitted as (0,2,1),(0,3,2).
static func quad(st: SurfaceTool, corners: Array, n: Vector3, col: Color, mat: int, part: int, pivot: Vector2, uvs := []) -> void:
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_normal(n)
		if uvs.is_empty():
			st.set_uv(Vector2(mat, part))
			st.set_uv2(pivot)
		else:
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(1, 0))
		st.add_vertex(corners[k])


static func box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, mat := 0, part := 0, pivot := Vector2.ZERO, basis := Basis()) -> void:
	var h := s * 0.5
	for f in FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corners := []
		for sv in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			corners.append(c + basis * ((n + u * sv[0] + v * sv[1]) * h))
		quad(st, corners, basis * n, col, mat, part, pivot)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


static func soldier_near() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := lin(0.9, 0.9, 0.86)
	var black := lin(0.06, 0.06, 0.06)
	var skin := lin(0.80, 0.62, 0.50)
	var brown := lin(0.36, 0.25, 0.15)
	var wood := lin(0.30, 0.20, 0.12)
	var steel := lin(0.7, 0.7, 0.75)
	box(st, Vector3(-0.1, 0.47, 0), Vector3(0.14, 0.8, 0.16), white, 3, 1, HIP)
	box(st, Vector3(0.1, 0.47, 0), Vector3(0.14, 0.8, 0.16), white, 3, 2, HIP)
	box(st, Vector3(-0.1, 0.06, -0.03), Vector3(0.13, 0.12, 0.24), black, 0, 1, HIP)
	box(st, Vector3(0.1, 0.06, -0.03), Vector3(0.13, 0.12, 0.24), black, 0, 2, HIP)
	box(st, Vector3(0, 1.16, 0), Vector3(0.4, 0.62, 0.24), white, 1)
	box(st, Vector3(0, 1.24, -0.125), Vector3(0.24, 0.36, 0.02), white, 2)
	box(st, Vector3(0, 0.78, 0.1), Vector3(0.36, 0.2, 0.06), white, 1)
	box(st, Vector3(-0.255, 1.13, -0.02), Vector3(0.11, 0.56, 0.13), white, 1)
	box(st, Vector3(0.255, 1.13, -0.02), Vector3(0.11, 0.56, 0.13), white, 1)
	box(st, Vector3(0, 1.57, -0.01), Vector3(0.17, 0.2, 0.19), skin)
	box(st, Vector3(0, 1.78, -0.01), Vector3(0.2, 0.23, 0.21), black)
	box(st, Vector3(0, 1.2, 0.18), Vector3(0.32, 0.36, 0.12), brown)
	box(st, Vector3(0.27, 1.55, -0.02), Vector3(0.04, 1.2, 0.05), wood, 0, 3, SHOULDER)
	box(st, Vector3(0.27, 2.32, -0.02), Vector3(0.015, 0.34, 0.015), steel, 0, 3, SHOULDER)
	box(st, Vector3(0.27, 2.2, -0.02), Vector3(0.22, 0.22, 0.22), white, 0, 5, SHOULDER)
	return _finish(st)


static func soldier_mid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := lin(0.9, 0.9, 0.86)
	var black := lin(0.06, 0.06, 0.06)
	var wood := lin(0.30, 0.20, 0.12)
	box(st, Vector3(-0.1, 0.43, 0), Vector3(0.15, 0.86, 0.16), white, 3, 1, HIP)
	box(st, Vector3(0.1, 0.43, 0), Vector3(0.15, 0.86, 0.16), white, 3, 2, HIP)
	box(st, Vector3(0, 1.17, 0.02), Vector3(0.52, 0.64, 0.3), white, 1)
	box(st, Vector3(0, 1.68, -0.01), Vector3(0.2, 0.36, 0.21), black)
	box(st, Vector3(0.27, 1.7, -0.02), Vector3(0.05, 1.6, 0.05), wood, 0, 3, SHOULDER)
	box(st, Vector3(0.27, 2.2, -0.02), Vector3(0.3, 0.3, 0.3), white, 0, 5, SHOULDER)
	return _finish(st)


## Far tier: one camera-facing card with shako / coat / trousers bands.
static func soldier_far() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.3
	var bands := [[0.0, 0.85, 3, lin(0.9, 0.9, 0.86)], [0.85, 1.5, 1, lin(0.9, 0.9, 0.86)], [1.5, 1.88, 0, lin(0.06, 0.06, 0.06)]]
	for b in bands:
		var y0: float = b[0]
		var y1: float = b[1]
		quad(st, [Vector3(-w, y0, 0), Vector3(w, y0, 0), Vector3(w, y1, 0), Vector3(-w, y1, 0)], Vector3(0, 0, 1), b[3], b[2], 4, Vector2.ZERO)
	return _finish(st)


## Furthest tier: unit box (x -0.5..0.5, y 0..1, z 0..1), subdivided so it can
## drape over terrain. Scaled per battalion in ribbon.gdshader.
static func ribbon() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color.WHITE
	var sx := 24
	var sz := 4
	for i in sx:
		var x0 := -0.5 + float(i) / sx
		var x1 := -0.5 + float(i + 1) / sx
		quad(st, [Vector3(x1, 0, 0), Vector3(x0, 0, 0), Vector3(x0, 1, 0), Vector3(x1, 1, 0)], Vector3(0, 0, -1), col, 0, 0, Vector2.ZERO)
		quad(st, [Vector3(x0, 0, 1), Vector3(x1, 0, 1), Vector3(x1, 1, 1), Vector3(x0, 1, 1)], Vector3(0, 0, 1), col, 0, 0, Vector2.ZERO)
		for j in sz:
			var z0 := float(j) / sz
			var z1 := float(j + 1) / sz
			quad(st, [Vector3(x0, 1, z0), Vector3(x0, 1, z1), Vector3(x1, 1, z1), Vector3(x1, 1, z0)], Vector3(0, 1, 0), col, 0, 0, Vector2.ZERO)
	for j in sz:
		var z0 := float(j) / sz
		var z1 := float(j + 1) / sz
		quad(st, [Vector3(0.5, 0, z1), Vector3(0.5, 0, z0), Vector3(0.5, 1, z0), Vector3(0.5, 1, z1)], Vector3(1, 0, 0), col, 0, 0, Vector2.ZERO)
		quad(st, [Vector3(-0.5, 0, z0), Vector3(-0.5, 0, z1), Vector3(-0.5, 1, z1), Vector3(-0.5, 1, z0)], Vector3(-1, 0, 0), col, 0, 0, Vector2.ZERO)
	return _finish(st)


## Pole plus a subdivided cloth (UV.x along the fly, UV2.x = 1 marks cloth).
static func flag() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(st, Vector3(0, 1.7, 0), Vector3(0.05, 3.4, 0.05), lin(0.35, 0.25, 0.15))
	box(st, Vector3(0, 3.45, 0), Vector3(0.1, 0.12, 0.1), lin(0.8, 0.65, 0.2))
	var w := 1.3
	var y0 := 2.25
	var y1 := 3.3
	var segs := 8
	for i in segs:
		var a := float(i) / segs
		var b := float(i + 1) / segs
		var corners := [Vector3(a * w, y0, 0), Vector3(b * w, y0, 0), Vector3(b * w, y1, 0), Vector3(a * w, y1, 0)]
		var uvs := [Vector2(a, 1), Vector2(b, 1), Vector2(b, 0), Vector2(a, 0)]
		quad(st, corners, Vector3(0, 0, 1), Color.WHITE, 0, 0, Vector2.ZERO, uvs)
	return _finish(st)


## Mounted figure for couriers and officers (vertex colours are sRGB).
static func rider(coat: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var horse := Color(0.33, 0.2, 0.11)
	var dark := Color(0.08, 0.06, 0.05)
	box(st, Vector3(0, 1.25, 0), Vector3(0.55, 0.62, 1.7), horse)
	for lx in [-0.18, 0.18]:
		for lz in [-0.62, 0.62]:
			box(st, Vector3(lx, 0.48, lz), Vector3(0.13, 0.96, 0.13), horse)
	box(st, Vector3(0, 1.72, -0.95), Vector3(0.28, 0.75, 0.34), horse, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, -0.6))
	box(st, Vector3(0, 1.98, -1.32), Vector3(0.24, 0.26, 0.58), horse, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, 0.5))
	box(st, Vector3(0, 1.3, 0.92), Vector3(0.1, 0.6, 0.12), dark, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, 0.4))
	box(st, Vector3(-0.27, 1.35, -0.05), Vector3(0.12, 0.55, 0.16), Color(0.85, 0.85, 0.8))
	box(st, Vector3(0.27, 1.35, -0.05), Vector3(0.12, 0.55, 0.16), Color(0.85, 0.85, 0.8))
	box(st, Vector3(0, 1.88, 0.02), Vector3(0.4, 0.62, 0.26), coat)
	box(st, Vector3(0, 2.3, 0.0), Vector3(0.18, 0.22, 0.2), Color(0.8, 0.62, 0.5))
	box(st, Vector3(0, 2.47, 0.0), Vector3(0.5, 0.14, 0.18), dark)
	return _finish(st)


## The player's own horse: neck, head and ears in front of the saddle camera.
static func horse_neck() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var horse := Color(0.36, 0.21, 0.11)
	var dark := Color(0.07, 0.05, 0.04)
	box(st, Vector3(0, -1.0, -0.75), Vector3(0.22, 0.3, 1.0), horse, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, 0.55))
	box(st, Vector3(0, -0.78, -0.7), Vector3(0.05, 0.09, 0.95), dark, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, 0.55))
	box(st, Vector3(0, -0.72, -1.36), Vector3(0.18, 0.22, 0.5), horse, 0, 0, Vector2.ZERO, Basis(Vector3.RIGHT, -0.9))
	box(st, Vector3(-0.06, -0.52, -1.2), Vector3(0.035, 0.11, 0.03), horse)
	box(st, Vector3(0.06, -0.52, -1.2), Vector3(0.035, 0.11, 0.03), horse)
	return _finish(st)
