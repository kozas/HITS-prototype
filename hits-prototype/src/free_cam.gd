extends Camera3D
## Debug spectator camera for inspecting the stress test from above.

var terrain
var yaw := 0.0
var pitch := -0.4
var base_speed := 80.0
var input_enabled := true


func setup(t) -> void:
	terrain = t
	near = 0.1
	far = 40000.0
	fov = 70.0


func place(p: Vector3, y: float, pt: float) -> void:
	position = p
	yaw = y
	pitch = pt
	rotation = Vector3(pitch, yaw, 0)


func look(rel: Vector2) -> void:
	yaw -= rel.x * 0.0025
	pitch = clampf(pitch - rel.y * 0.0025, -1.5, 1.5)


func update(dt: float) -> void:
	rotation = Vector3(pitch, yaw, 0)
	if not input_enabled:
		return
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		v -= basis.z
	if Input.is_key_pressed(KEY_S):
		v += basis.z
	if Input.is_key_pressed(KEY_A):
		v -= basis.x
	if Input.is_key_pressed(KEY_D):
		v += basis.x
	if Input.is_key_pressed(KEY_E):
		v += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		v -= Vector3.UP
	var s := base_speed * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	position += v.normalized() * s * dt if v != Vector3.ZERO else Vector3.ZERO
	position.y = maxf(position.y, terrain.height(position.x, position.z) + 2.0)
