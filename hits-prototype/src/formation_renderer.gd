extends Node3D
## Draws every battalion. Work here is O(battalions) per frame. Men exist only
## as GPU instances whose layout soldier.gdshader computes from instance uniforms.
##
## Per battalion: root Node3D (anchor transform)
##   ├─ MultiMeshInstance3D: one instance per man (NEAR / MID / FAR tiers)
##   ├─ MultiMeshInstance3D staff: officers, NCOs, drummers, colour guard (NEAR / MID)
##   ├─ MeshInstance3D ribbon: whole battalion as one box (RIBBON tier)
##   └─ MeshInstance3D flag

const Formation = preload("res://src/formation.gd")
const Meshes = preload("res://src/meshes.gd")
const T := Formation.Type

enum Tier { NEAR, MID, FAR, RIBBON, HIDDEN }
const TIER_NAMES := ["near", "mid", "far", "ribbon", "hidden"]
const LOD_MODES := ["auto", "force NEAR", "force MID", "force FAR", "force RIBBON"]

var dist_near := 220.0
var dist_mid := 750.0
var dist_far := 1700.0
var lod_mode := 0
var los_enabled := true
var los_per_frame := 12

var terrain
var soldier_mat: ShaderMaterial
var staff_mat: ShaderMaterial
var ribbon_mat: ShaderMaterial
var flag_mat: ShaderMaterial
var tier_meshes: Array = []
var mesh_ribbon: ArrayMesh
var mesh_staff: ArrayMesh
var mesh_flag: ArrayMesh
var entries: Array = []
var tier_men := [0, 0, 0, 0, 0]
var tier_bns := [0, 0, 0, 0, 0]
var los_usec := 0
var _los_cursor := 0
var _identity := {}


class Entry:
	var f: Formation
	var root: Node3D
	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var staff: MultiMeshInstance3D
	var ribbon: MeshInstance3D
	var flag: MeshInstance3D
	var tier := -1
	var last_p := Vector2(INF, INF)
	var last_yaw := INF
	var last_ftype := -1
	var flag_from := Vector2.ZERO
	var flag_to := Vector2.ZERO
	var flag_moving := false


func setup(t, formations: Array, brigades: Array) -> void:
	terrain = t
	soldier_mat = _material("res://shaders/soldier.gdshader")
	staff_mat = _material("res://shaders/soldier.gdshader")
	staff_mat.set_shader_parameter("staff", true)
	mesh_staff = Meshes.staff()
	ribbon_mat = _material("res://shaders/ribbon.gdshader")
	flag_mat = _material("res://shaders/flag.gdshader")
	tier_meshes = [Meshes.soldier_near(), Meshes.soldier_mid(), Meshes.soldier_far()]
	mesh_ribbon = Meshes.ribbon()
	mesh_flag = Meshes.flag()
	for f in formations:
		_create(f, brigades[f.brigade])


## A formation that joined the battle after setup (skirmishers thrown out).
func add_formation(f, b) -> void:
	_create(f, b)


## Drives every soldier animation; call once per frame with the render-time clock.
func set_sim_time(t: float) -> void:
	soldier_mat.set_shader_parameter("sim_time", t)
	staff_mat.set_shader_parameter("sim_time", t)


func _material(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	terrain.apply_height_params(m)
	return m


## Uniform colours by army, with a few distinctive brigades (light infantry, rifles).
static func palette(army: int, brigade_id: int) -> Array:
	if army == 0:
		if brigade_id % 7 == 5:
			return [Meshes.lin(0.08, 0.11, 0.36), Meshes.lin(0.08, 0.11, 0.36), Meshes.lin(0.1, 0.13, 0.38)]
		return [Meshes.lin(0.10, 0.14, 0.42), Meshes.lin(0.92, 0.92, 0.88), Meshes.lin(0.9, 0.9, 0.86)]
	if brigade_id % 9 == 4:
		return [Meshes.lin(0.12, 0.2, 0.1), Meshes.lin(0.05, 0.05, 0.05), Meshes.lin(0.12, 0.2, 0.1)]
	return [Meshes.lin(0.62, 0.07, 0.06), Meshes.lin(0.85, 0.8, 0.6), Meshes.lin(0.32, 0.33, 0.36)]


func _identity_buffer(count: int) -> PackedFloat32Array:
	if not _identity.has(count):
		var buf := PackedFloat32Array()
		buf.resize(count * 12)
		for i in count:
			buf[i * 12] = 1.0
			buf[i * 12 + 5] = 1.0
			buf[i * 12 + 10] = 1.0
		_identity[count] = buf
	return _identity[count]


func _create(f, b) -> void:
	var e := Entry.new()
	e.f = f
	e.root = Node3D.new()
	add_child(e.root)

	# Instance transforms are identity and never change: INSTANCE_ID is the slot.
	e.mm = MultiMesh.new()
	e.mm.transform_format = MultiMesh.TRANSFORM_3D
	e.mm.mesh = tier_meshes[Tier.MID]
	e.mm.instance_count = f.max_strength
	e.mm.buffer = _identity_buffer(f.max_strength)
	e.mm.visible_instance_count = f.strength
	e.mmi = MultiMeshInstance3D.new()
	e.mmi.multimesh = e.mm
	e.mmi.material_override = soldier_mat
	# Big enough for any formation it can take (open order is the widest).
	var half_w: float = maxf(140.0, f.footprint_as(T.OPEN).x * 0.5 + 20.0) if f.is_skirmisher else 140.0
	e.mmi.custom_aabb = AABB(Vector3(-half_w, -40, -60), Vector3(half_w * 2.0, 80, 260))
	e.root.add_child(e.mmi)

	# 5 per company (captain, lieutenant, 2 sergeants, drummer) + 12 battalion staff.
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = mesh_staff
	smm.instance_count = 5 * f.companies + 12
	smm.buffer = _identity_buffer(smm.instance_count)
	e.staff = MultiMeshInstance3D.new()
	e.staff.multimesh = smm
	e.staff.material_override = staff_mat
	e.staff.custom_aabb = e.mmi.custom_aabb
	e.root.add_child(e.staff)

	e.ribbon = MeshInstance3D.new()
	e.ribbon.mesh = mesh_ribbon
	e.ribbon.material_override = ribbon_mat
	e.ribbon.custom_aabb = e.mmi.custom_aabb
	e.ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.root.add_child(e.ribbon)

	e.flag = MeshInstance3D.new()
	e.flag.mesh = mesh_flag
	e.flag.material_override = flag_mat
	e.flag.custom_aabb = AABB(Vector3(-2, -40, -2), Vector3(4, 80, 4))
	e.flag.set_instance_shader_parameter("flag_style", float(f.army))
	e.root.add_child(e.flag)

	var cols := palette(f.army, b.id)
	for node in [e.mmi, e.staff, e.ribbon]:
		node.set_instance_shader_parameter("coat_color", cols[0])
		node.set_instance_shader_parameter("trim_color", cols[1])
		node.set_instance_shader_parameter("trouser_color", cols[2])
	f.set_meta("coat", cols[0])
	entries.append(e)


## lod_scale > 1 when looking through the telescope: things inside its field of
## view (direction view_dir, cos of the half-angle view_cos) look that much
## closer, so they get the detail tier of the apparent distance.
func update(cam: Vector3, alpha: float, time: float, lod_scale := 1.0, view_dir := Vector3.FORWARD, view_cos := 1.0) -> void:
	for k in 5:
		tier_men[k] = 0
		tier_bns[k] = 0
	var t0 := Time.get_ticks_usec()
	_update_los(cam, time)
	los_usec = Time.get_ticks_usec() - t0

	for e: Entry in entries:
		var f: Formation = e.f
		if f.dead:
			if e.root.visible:
				e.root.visible = false
				e.tier = Tier.HIDDEN
			continue
		var p: Vector2 = f.pos
		var yaw: float = f.facing
		if f.prev_pos != f.pos or f.prev_facing != f.facing:
			p = f.prev_pos.lerp(f.pos, alpha)
			yaw = lerp_angle(f.prev_facing, f.facing, alpha)
		if p != e.last_p or yaw != e.last_yaw:
			e.last_p = p
			e.last_yaw = yaw
			e.root.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, terrain.height(p.x, p.y), p.y))
		var dx: float = f.cpos.x - cam.x
		var dz: float = f.cpos.y - cam.z
		var dy: float = e.root.position.y - cam.y
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		if lod_scale > 1.0 and dx * view_dir.x + dy * view_dir.y + dz * view_dir.z > view_cos * d:
			d /= lod_scale
		var tier := _pick_tier(d, e.tier)
		if los_enabled and not f.los_visible:
			tier = Tier.HIDDEN
		if tier != e.tier:
			_apply_tier(e, tier)
		if f.render_dirty:
			_push(e)
		if e.flag_moving:
			var k := clampf((time - f.trans_start) / maxf(f.trans_dur, 0.1), 0.0, 1.0)
			var fp: Vector2 = e.flag_from.lerp(e.flag_to, k)
			e.flag.position = Vector3(fp.x, 0, fp.y)
			e.flag_moving = k < 1.0
		tier_men[tier] += f.strength
		tier_bns[tier] += 1


func _pick_tier(d: float, cur: int) -> int:
	if lod_mode > 0:
		return lod_mode - 1
	var out := _tier_for(d / 1.05)
	var inn := _tier_for(d / 0.95)
	if cur < 0 or cur >= Tier.HIDDEN:
		return _tier_for(d)
	if out > cur:
		return out
	if inn < cur:
		return inn
	return cur


func _tier_for(d: float) -> int:
	if d < dist_near:
		return Tier.NEAR
	if d < dist_mid:
		return Tier.MID
	if d < dist_far:
		return Tier.FAR
	return Tier.RIBBON


func _apply_tier(e: Entry, t: int) -> void:
	e.tier = t
	if t == Tier.HIDDEN:
		e.root.visible = false
		return
	e.root.visible = true
	var men := t <= Tier.FAR
	e.mmi.visible = men
	e.staff.visible = t <= Tier.MID
	# Skirmishers carry no colours, and a scattered chain is no solid block.
	e.ribbon.visible = t == Tier.RIBBON and not e.f.is_skirmisher
	e.flag.visible = t != Tier.RIBBON and not e.f.is_skirmisher
	if men:
		e.mm.mesh = tier_meshes[t]
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if t == Tier.NEAR else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.mmi.cast_shadow = shadow
		e.staff.cast_shadow = shadow


## Event-driven: only called when the sim marks the battalion dirty.
func _push(e: Entry) -> void:
	var f: Formation = e.f
	f.render_dirty = false
	var cadence: float = f.speed() / Formation.ORDINARY_STEP if f.moving else 1.0
	var form_state := Vector4(f.ftype_from, f.ftype, f.trans_start, f.absent_mask)
	var form_dims := Vector4(f.layout_strength(), f.ranks, f.id, f.companies)
	var anim_state := Vector4(1.0 if f.moving else 0.0, f.last_volley, f.rout_t, cadence)
	var continuous: bool = f.fire_now == Formation.Fire.PLATOON or f.fire_now == Formation.Fire.AT_WILL
	var drill_state := Vector4(f.moving_since, f.fire_now if continuous else 0, f.fire_start, f.fire_end)
	for node in [e.mmi, e.staff]:
		node.set_instance_shader_parameter("form_state", form_state)
		node.set_instance_shader_parameter("form_dims", form_dims)
		node.set_instance_shader_parameter("anim_state", anim_state)
		node.set_instance_shader_parameter("drill_state", drill_state)
	e.mm.visible_instance_count = f.layout_strength()
	var fp: Vector2 = f.footprint()
	e.ribbon.set_instance_shader_parameter("ribbon_dims", Vector4(fp.x, fp.y, 0.0, 0.0))
	if f.ftype != e.last_ftype:
		# The colours march with their guard: tweened over the change of formation.
		e.flag_from = f.colour_pos(f.ftype_from if e.last_ftype >= 0 else f.ftype)
		e.flag_to = f.colour_pos(f.ftype)
		e.last_ftype = f.ftype
		e.flag_moving = true


## Round-robin line of sight from the player's eye to each battalion (centre and
## both flanks). Hidden battalions are not drawn, and what *is* seen updates the
## player's knowledge of the enemy.
func _update_los(cam: Vector3, time: float) -> void:
	var n := entries.size()
	if n == 0:
		return
	if not los_enabled:
		for e in entries:
			_mark_seen(e.f, time)
		return
	for k in mini(los_per_frame, n):
		_los_cursor = (_los_cursor + 1) % n
		var f: Formation = entries[_los_cursor].f
		if f.dead:
			continue
		f.los_visible = _check_los(cam, f)
		if f.los_visible:
			_mark_seen(f, time)


func _check_los(cam: Vector3, f: Formation) -> bool:
	var c: Vector2 = f.cpos
	var d := Vector2(cam.x, cam.z).distance_to(c)
	if d < 200.0:
		return true
	var steps := clampi(int(d / 90.0), 6, 28)
	var half: float = f.footprint().x * 0.45
	for off in [0.0, -half, half]:
		var p: Vector2 = c + f.right() * off
		var target := Vector3(p.x, terrain.height(p.x, p.y) + 3.0, p.y)
		if terrain.line_of_sight(cam, target, steps):
			return true
	return false


func _mark_seen(f, time: float) -> void:
	f.seen_time = time
	f.seen_pos = f.pos
	f.seen_facing = f.facing
	f.seen_ftype = f.ftype
