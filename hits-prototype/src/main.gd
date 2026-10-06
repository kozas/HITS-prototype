extends Node3D
## M0 stress test bootstrap: builds the world, owns the frame loop, input,
## HUD and the scripted benchmark (run with `-- --bench`).

const Terrain = preload("res://src/terrain.gd")
const BattleSim = preload("res://src/battle_sim.gd")
const FormationRenderer = preload("res://src/formation_renderer.gd")
const Smoke = preload("res://src/smoke.gd")
const Corpses = preload("res://src/corpses.gd")
const Couriers = preload("res://src/couriers.gd")
const PlayerRider = preload("res://src/player_rider.gd")
const FreeCam = preload("res://src/free_cam.gd")
const MapOverlay = preload("res://src/map_overlay.gd")
const Hud = preload("res://src/hud.gd")
const Meshes = preload("res://src/meshes.gd")
const Formation = preload("res://src/formation.gd")

const PLAYER_ARMY := 0
const TIME_SCALES := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]

var terrain
var sim
var renderer
var smoke
var corpses
var couriers
var player
var free_cam
var map
var hud

var bns_per_side := 160
var men := 600
var front_z := 700.0

var time_scale_idx := 1
var paused := false
var using_free_cam := false
var player_orders: Array = []
var _last_dust := 0
var _hud_t := 0.0
var _sim_usec := 0
var _render_usec := 0
var _vp: RID

var bench := false
var bench_shots := ""
var bench_out := ""
var _ts_override := -1.0
var _bench_segments: Array = []
var _bench_idx := -1
var _bench_t := 0.0
var _bench_rec := {}
var _bench_results: Array = []


func _ready() -> void:
	_parse_args()
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_setup_environment()

	var t0 := Time.get_ticks_msec()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(1815)

	sim = BattleSim.new(terrain)
	sim.deploy(bns_per_side, men, front_z)
	sim._rebuild_grid()

	renderer = FormationRenderer.new()
	add_child(renderer)
	renderer.setup(terrain, sim.formations, sim.brigades)

	smoke = Smoke.new()
	add_child(smoke)
	smoke.setup()

	corpses = Corpses.new()
	add_child(corpses)
	corpses.setup(renderer.tier_meshes[1])

	couriers = Couriers.new()
	add_child(couriers)
	couriers.setup(sim, terrain)
	couriers.notify = func(text: String) -> void: hud.toast(text)
	sim.order_sink = func(o: Dictionary) -> void: couriers.dispatch(o, _hq_for(o.army))

	_place_enemy_hq()

	player = PlayerRider.new()
	add_child(player)
	player.setup(terrain, Vector2(120, front_z + 380), 0.0)
	free_cam = FreeCam.new()
	add_child(free_cam)
	free_cam.setup(terrain)
	free_cam.place(Vector3(0, 420, front_z + 1500), 0.0, -0.3)
	player.camera.current = true

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hud.setup()
	map = MapOverlay.new()
	ui.add_child(map)
	map.setup(self)

	print("HITS M0: %d battalions, %d men, built in %d ms" % [sim.formations.size(), sim.soldiers_alive(), Time.get_ticks_msec() - t0])
	if bench:
		_bench_init()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.toast("11:00. The armies are deploying. Press M for the map.")


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--bench":
			bench = true
			front_z = 450.0
		elif a.begins_with("--bns="):
			bns_per_side = int(a.get_slice("=", 1))
		elif a.begins_with("--men="):
			men = int(a.get_slice("=", 1))
		elif a.begins_with("--shots="):
			bench_shots = a.get_slice("=", 1)
		elif a.begins_with("--bench-out="):
			bench_out = a.get_slice("=", 1)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.5, 0.72)
	psm.sky_horizon_color = Color(0.74, 0.77, 0.8)
	psm.ground_horizon_color = Color(0.68, 0.72, 0.74)
	psm.ground_bottom_color = Color(0.4, 0.45, 0.36)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.75, 0.8)
	env.fog_density = 0.00016
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)


func _place_enemy_hq() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var m := Meshes.rider(Color(0.55, 0.07, 0.06))
	var hq: Vector2 = sim.hq[1]
	for k in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		var p := hq + Vector2(k * 4.0 - 10.0, (k % 2) * 3.0)
		mi.position = Vector3(p.x, terrain.height(p.x, p.y), p.y)
		mi.rotation.y = PI
		add_child(mi)


func player_xz() -> Vector2:
	return Vector2(player.position.x, player.position.z)


func _hq_for(army: int) -> Vector2:
	return player_xz() if army == PLAYER_ARMY else sim.hq[army]


func issue_player_order(brigade_id: int, dest: Vector2, facing: float, ftype: int) -> void:
	var b = sim.brigades[brigade_id]
	var o: Dictionary = sim.make_order(b, dest, facing, ftype)
	player_orders.append(o)
	couriers.dispatch(o, player_xz())
	var dist: float = player_xz().distance_to(b.centroid())
	hud.toast("Courier rides for %s (%s, %.1f km away)" % [b.label, Formation.TYPE_NAMES[ftype], dist / 1000.0])


func clock_text() -> String:
	var s := int(sim.time) + 11 * 3600
	var ts: float = _ts_override if _ts_override >= 0.0 else TIME_SCALES[time_scale_idx]
	return "%02d:%02d:%02d  %s" % [s / 3600, (s / 60) % 60, s % 60, "PAUSED" if paused else "x%s" % str(ts)]


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if bench:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if using_free_cam:
			free_cam.look(rel)
		else:
			player.look(rel)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not map.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_M, KEY_TAB:
				_toggle_map()
			KEY_ESCAPE:
				if map.visible:
					_toggle_map()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				_set_free_cam(not using_free_cam)
			KEY_EQUAL, KEY_KP_ADD:
				time_scale_idx = mini(time_scale_idx + 1, TIME_SCALES.size() - 1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				time_scale_idx = maxi(time_scale_idx - 1, 0)
			KEY_P:
				paused = not paused
			KEY_L:
				renderer.lod_mode = (renderer.lod_mode + 1) % FormationRenderer.LOD_MODES.size()
				hud.toast("LOD: " + FormationRenderer.LOD_MODES[renderer.lod_mode])
			KEY_O:
				renderer.los_enabled = not renderer.los_enabled
				hud.toast("LOS culling " + ("on" if renderer.los_enabled else "off"))
			KEY_K:
				sim.chaos()
				hud.toast("Chaos: every battalion changes formation")
			KEY_G:
				sim.ai_enabled[PLAYER_ARMY] = not sim.ai_enabled[PLAYER_ARMY]
				hud.toast("Autopilot for your army " + ("on" if sim.ai_enabled[PLAYER_ARMY] else "off"))
			KEY_H:
				hud.help.visible = not hud.help.visible
			KEY_1, KEY_2, KEY_3, KEY_4:
				map.order_ftype = (event as InputEventKey).keycode - KEY_1


func _toggle_map() -> void:
	map.visible = not map.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map.visible else Input.MOUSE_MODE_CAPTURED


func _set_free_cam(on: bool) -> void:
	using_free_cam = on
	if on:
		free_cam.place(player.camera.global_position, player.yaw, player.pitch)
		free_cam.current = true
	else:
		player.camera.current = true


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if bench:
		_bench_step(delta)
	var ts: float = _ts_override if _ts_override >= 0.0 else TIME_SCALES[time_scale_idx]
	if paused:
		ts = 0.0
	var t0 := Time.get_ticks_usec()
	sim.advance(delta * ts)
	couriers.update(delta * ts, sim.time)
	_consume_events()
	if int(sim.time) != _last_dust:
		_last_dust = int(sim.time)
		smoke.update_dust(sim.formations, sim.time, terrain)
	var t1 := Time.get_ticks_usec()

	player.input_enabled = not map.visible and not using_free_cam and not bench
	free_cam.input_enabled = using_free_cam and not map.visible and not bench
	player.update(delta)
	free_cam.update(delta)
	var cam: Camera3D = free_cam if using_free_cam else player.camera
	var render_time: float = sim.time - BattleSim.TICK * (1.0 - sim.alpha())
	renderer.update(cam.global_position, sim.alpha(), sim.time)
	renderer.soldier_mat.set_shader_parameter("sim_time", render_time)
	smoke.mat.set_shader_parameter("sim_time", render_time)
	var t2 := Time.get_ticks_usec()
	_sim_usec = t1 - t0
	_render_usec = t2 - t1

	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.25
		_update_hud()


func _consume_events() -> void:
	for ev in sim.events:
		match ev.type:
			"volley":
				smoke.on_volley(ev.f, ev.t, terrain)
			"casualties":
				corpses.add(ev.f, ev.n, terrain)
			"rout":
				if ev.f.army == PLAYER_ARMY and not bench:
					hud.toast("Battalion %s (%s) is breaking!" % [ev.f.label, sim.brigades[ev.f.brigade].label])
	sim.events.clear()


func _update_hud() -> void:
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var tb: Array = renderer.tier_bns
	var tm: Array = renderer.tier_men
	var lines := [
		"FPS %d   GPU %.1f ms   draw calls %d   primitives %.2f M" % [Engine.get_frames_per_second(), gpu, draws, prims / 1.0e6],
		"script: sim+couriers %.2f ms   render sync %.2f ms (LOS %.2f)" % [_sim_usec / 1000.0, _render_usec / 1000.0, renderer.los_usec / 1000.0],
		"men alive %d  (French %d / Allied %d)   battalions %d   fallen %d" % [sim.soldiers_alive(), sim.soldiers_alive(0), sim.soldiers_alive(1), sim.formations.size(), corpses.total],
		"near %d bn / %dk men | mid %d / %dk | far %d / %dk | ribbon %d / %dk | hidden %d / %dk" % [tb[0], tm[0] / 1000, tb[1], tm[1] / 1000, tb[2], tm[2] / 1000, tb[3], tm[3] / 1000, tb[4], tm[4] / 1000],
		"LOD %s   LOS culling %s   smoke puffs %d   couriers riding %d (delivered %d, lost %d)" % [FormationRenderer.LOD_MODES[renderer.lod_mode], "on" if renderer.los_enabled else "off", smoke.live_estimate(), couriers.riding_count(PLAYER_ARMY), couriers.delivered, couriers.lost],
		("free camera" if using_free_cam else "in the saddle: %s" % player.gait()) + ("   autopilot ON" if sim.ai_enabled[PLAYER_ARMY] else ""),
	]
	hud.stats.text = "\n".join(lines)
	hud.stats.visible = not map.visible
	hud.clock.text = clock_text()


# ---------------------------------------------------------------- benchmark

func _bench_init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	sim.ai_enabled[PLAYER_ARMY] = true
	_bench_segments = [
		{"name": "warmup: battle develops at x16", "dur": 45.0, "ts": 16.0, "rec": false, "cam": "overview", "lod": 0, "los": true},
		{"name": "saddle, behind own lines", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "rear", "lod": 0, "los": true},
		{"name": "saddle, in the firing line", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "front", "lod": 0, "los": true},
		{"name": "overview 400 m, auto LOD", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "overview", "lod": 0, "los": true},
		{"name": "overview, force NEAR (worst case)", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "overview", "lod": 1, "los": true},
		{"name": "overview, force MID", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "overview", "lod": 2, "los": true},
		{"name": "overview, force FAR", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "overview", "lod": 3, "los": true},
		{"name": "overview, force RIBBON", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "overview", "lod": 4, "los": true},
		{"name": "saddle, behind lines, LOS cull OFF", "dur": 8.0, "ts": 2.0, "rec": true, "cam": "rear", "lod": 0, "los": false},
		{"name": "sim only at x16 (overview, auto)", "dur": 8.0, "ts": 16.0, "rec": true, "cam": "overview", "lod": 0, "los": true},
		{"name": "map overlay", "dur": 3.0, "ts": 2.0, "rec": false, "cam": "map", "lod": 0, "los": true},
		{"name": "chaos: formation changes close up", "dur": 8.0, "ts": 3.0, "rec": false, "cam": "chaos", "lod": 0, "los": true},
	]
	_bench_next()


func _bench_next() -> void:
	_bench_idx += 1
	if _bench_idx >= _bench_segments.size():
		_bench_finish()
		return
	var seg: Dictionary = _bench_segments[_bench_idx]
	_bench_t = 0.0
	_bench_rec = {"ms": [], "gpu": 0.0, "script": 0.0, "draws": 0.0, "prims": 0.0, "n": 0, "shot": false}
	_ts_override = seg.ts
	renderer.lod_mode = seg.lod
	renderer.los_enabled = seg.los
	map.visible = seg.cam == "map"
	var f = _most_engaged()
	match seg.cam:
		"overview", "map":
			_set_free_cam(true)
			free_cam.place(Vector3(0, 300, 1150), 0.0, -0.27)
		"chaos":
			sim.chaos()
			_set_free_cam(true)
			if f != null:
				var p: Vector2 = f.cpos + f.back() * 90.0
				free_cam.place(Vector3(p.x, terrain.height(p.x, p.y) + 55.0, p.y), f.facing, -0.5)
		"rear":
			_set_free_cam(false)
			if f != null:
				player.place(f.pos + f.back() * 380.0 + f.right() * 60.0, f.facing)
		"front":
			_set_free_cam(false)
			if f != null:
				player.place(f.pos + f.back() * (f.footprint().y + 25.0) + f.right() * f.footprint().x * 0.3, f.facing - 0.25)
	print("[bench] %s" % seg.name)


func _most_engaged():
	var best = null
	var bd := INF
	for f in sim.formations:
		if f.dead or f.army != PLAYER_ARMY or f.routing:
			continue
		var e = sim.nearest_enemy(f.cpos, f.army, 2000.0)
		if e == null:
			continue
		var d: float = e.cpos.distance_to(f.cpos)
		if d < bd:
			bd = d
			best = f
	return best


func _bench_step(delta: float) -> void:
	if _bench_idx >= _bench_segments.size():
		return
	var seg: Dictionary = _bench_segments[_bench_idx]
	_bench_t += delta
	if seg.rec and _bench_t > 1.5:
		_bench_rec.ms.append(delta * 1000.0)
		_bench_rec.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_bench_rec.script += (_sim_usec + _render_usec) / 1000.0
		_bench_rec.draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_bench_rec.prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_bench_rec.n += 1
	if bench_shots != "" and not _bench_rec.shot and _bench_t > seg.dur * 0.6:
		_bench_rec.shot = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(bench_shots.path_join("%02d_%s.png" % [_bench_idx, seg.cam + "_lod%d" % seg.lod]))
	if _bench_t >= seg.dur:
		if seg.rec:
			_bench_results.append(_bench_summary(seg))
		_bench_next()


func _bench_summary(seg: Dictionary) -> Dictionary:
	var ms: Array = _bench_rec.ms
	var n: int = maxi(_bench_rec.n, 1)
	var sorted := ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in ms:
		total += v
	var avg: float = total / maxi(ms.size(), 1)
	var p99: float = sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if not sorted.is_empty() else 0.0
	var tm: Array = renderer.tier_men
	return {
		"name": seg.name, "fps": 1000.0 / maxf(avg, 0.001), "avg": avg, "p99": p99,
		"gpu": _bench_rec.gpu / n, "script": _bench_rec.script / n,
		"draws": _bench_rec.draws / n, "prims": _bench_rec.prims / n / 1.0e6,
		"tiers": "%dk/%dk/%dk/%dk/%dk" % [tm[0] / 1000, tm[1] / 1000, tm[2] / 1000, tm[3] / 1000, tm[4] / 1000],
	}


func _bench_finish() -> void:
	var size := get_viewport().get_visible_rect().size
	var out := []
	out.append("HITS M0 benchmark  |  %s  |  %dx%d  |  %d battalions, %d men at start, %d alive, %d fallen" % [
		RenderingServer.get_video_adapter_name(), size.x, size.y, sim.formations.size(),
		sim.formations.size() * men, sim.soldiers_alive(), corpses.total])
	out.append("%-36s %7s %8s %8s %8s %9s %7s %8s  %s" % ["segment", "fps", "avg ms", "p99 ms", "GPU ms", "script ms", "draws", "prims M", "men near/mid/far/ribbon/hidden"])
	for r in _bench_results:
		out.append("%-36s %7.1f %8.2f %8.2f %8.2f %9.2f %7d %8.2f  %s" % [r.name, r.fps, r.avg, r.p99, r.gpu, r.script, int(r.draws), r.prims, r.tiers])
	var text := "\n".join(out)
	print(text)
	if bench_out != "":
		var fa := FileAccess.open(bench_out, FileAccess.WRITE)
		if fa:
			fa.store_string(text + "\n")
	get_tree().quit()
