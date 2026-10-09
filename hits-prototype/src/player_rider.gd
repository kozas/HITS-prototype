extends Node3D
## The general in the saddle. Moves in real time (see DESIGN.md §10.1).

const Meshes = preload("res://src/meshes.gd")
const EYE := 2.45
const LIMIT := 3000.0
const FOV := 70.0
const MAGNIFICATION_RANGE := Vector2(4.0, 20.0)

var terrain
var body: Node3D
var camera: Camera3D
var neck: MeshInstance3D
var yaw := 0.0
var pitch := -0.04
var speed := 0.0
var input_enabled := true
## Spyglass: the general halts to use it; the view narrows by the magnification.
var telescope := false
var magnification := 10.0
var _bob := 0.0
var _t := 0.0


func setup(t, start: Vector2, start_yaw: float) -> void:
	terrain = t
	yaw = start_yaw
	body = Node3D.new()
	add_child(body)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 40000.0
	camera.fov = FOV
	body.add_child(camera)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.7
	neck = MeshInstance3D.new()
	neck.mesh = Meshes.horse_neck()
	neck.material_override = mat
	body.add_child(neck)
	place(start, start_yaw)


func place(p: Vector2, y: float) -> void:
	position = Vector3(p.x, terrain.height(p.x, p.y) + EYE, p.y)
	yaw = y
	speed = 0.0


func look(rel: Vector2) -> void:
	var k := 0.0025 / lod_scale()
	yaw -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.2, 1.1)


func set_telescope(on: bool) -> void:
	telescope = on
	neck.visible = not on
	_apply_fov()


## Mouse wheel: x1.25 or /1.25 per notch.
func change_magnification(factor: float) -> void:
	magnification = clampf(magnification * factor, MAGNIFICATION_RANGE.x, MAGNIFICATION_RANGE.y)
	_apply_fov()


## How much bigger things look than to the naked eye; the renderer divides
## distances by this when choosing detail.
func lod_scale() -> float:
	return magnification if telescope else 1.0


func _apply_fov() -> void:
	var half := tan(deg_to_rad(FOV * 0.5)) / lod_scale()
	camera.fov = rad_to_deg(2.0 * atan(half))


func gait() -> String:
	var s := absf(speed)
	if s < 0.2:
		return "halted"
	if s < 2.5:
		return "walk"
	if s < 6.0:
		return "trot"
	return "gallop"


func update(dt: float) -> void:
	var target := 0.0
	var strafe := 0.0
	if input_enabled and not telescope:
		if Input.is_key_pressed(KEY_W):
			target = 11.0 if Input.is_key_pressed(KEY_SHIFT) else (1.7 if Input.is_key_pressed(KEY_CTRL) else 4.0)
		elif Input.is_key_pressed(KEY_S):
			target = -1.2
		if Input.is_key_pressed(KEY_A):
			strafe -= 1.2
		if Input.is_key_pressed(KEY_D):
			strafe += 1.2
	speed = move_toward(speed, target, dt * (2.5 if absf(target) > absf(speed) else 5.0))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var rt := Vector3(cos(yaw), 0, -sin(yaw))
	position += (fwd * speed + rt * strafe) * dt
	position.x = clampf(position.x, -LIMIT, LIMIT)
	position.z = clampf(position.z, -LIMIT, LIMIT)
	position.y = terrain.height(position.x, position.z) + EYE
	_bob += dt * (1.5 + absf(speed) * 0.8)
	var amp := clampf(absf(speed) * 0.011, 0.0, 0.09)
	body.rotation = Vector3(0, yaw, 0)
	_t += dt
	var sway := Vector2.ZERO
	if telescope:
		# A hand-held glass is never quite still.
		sway = Vector2(sin(_t * 1.3) + 0.5 * sin(_t * 3.1), sin(_t * 1.7) + 0.5 * sin(_t * 2.3)) * 0.00025
	camera.rotation = Vector3(pitch + sway.y, sway.x, 0)
	camera.position = Vector3(0, sin(_bob * 2.0) * amp, 0)
	neck.position = Vector3(0, sin(_bob * 2.0 + 0.6) * amp * 1.4, 0)
	neck.rotation = Vector3(sin(_bob * 2.0) * amp * 0.8, 0, 0)
