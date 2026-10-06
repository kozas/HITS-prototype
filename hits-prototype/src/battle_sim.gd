extends RefCounted
## Formation-level battle simulation. Fixed 10 Hz tick, independent of frame
## rate (needed for time compression). Nothing here scales with the number of
## men, only with the number of battalions.

const Formation = preload("res://src/formation.gd")
const T := Formation.Type

const TICK := 0.1
const CELL := 300.0
const FIRE_RANGE := 180.0
const MAP_LIMIT := 2900.0


class Brigade:
	var id := 0
	var army := 0
	var label := ""
	var row := 0
	var battalions: Array = []
	var pending: Array = []
	var current = null
	var awaiting := false
	var ai_next := 0.0

	func alive() -> Array:
		var out := []
		for f in battalions:
			if not f.dead:
				out.append(f)
		return out

	func centroid() -> Vector2:
		var c := Vector2.ZERO
		var n := 0
		for f in battalions:
			if not f.dead:
				c += f.center()
				n += 1
		return c / n if n > 0 else Vector2.ZERO


var terrain
var formations: Array = []
var brigades: Array = []
var time := 0.0
var accum := 0.0
var tick_count := 0
var events: Array = []
var ai_enabled := [false, true]
var hq := [Vector2.ZERO, Vector2.ZERO]
## Callable(order: Dictionary): hands AI orders to the courier system.
var order_sink: Callable
var _grid := {}
var _hits: Array = []
var _order_id := 0
var rng := RandomNumberGenerator.new()


func _init(t) -> void:
	terrain = t
	rng.seed = 1815


# ---------------------------------------------------------------- deployment

func deploy(bns_per_side: int, men: int, front_z: float) -> void:
	var per_brigade := 4
	var per_row := 6
	var brig_count := ceili(float(bns_per_side) / per_brigade)
	for army in 2:
		var sgn := 1.0 if army == 0 else -1.0
		var yaw := 0.0 if army == 0 else PI
		var right := Vector2(cos(yaw), -sin(yaw))
		hq[army] = Vector2(0, sgn * (front_z + 950.0))
		var made := 0
		for bi in brig_count:
			var row := bi / per_row
			var col := bi % per_row
			var in_row := mini(per_row, brig_count - row * per_row)
			var bx := (col - (in_row - 1) * 0.5) * 640.0
			var bz := sgn * (front_z + row * 260.0)
			var b := Brigade.new()
			b.id = brigades.size()
			b.army = army
			b.row = row
			b.label = "%s Bde %d" % ["Fr" if army == 0 else "Al", bi + 1]
			b.ai_next = rng.randf_range(20.0, 120.0)
			brigades.append(b)
			for k in per_brigade:
				if made >= bns_per_side:
					break
				var f := Formation.new()
				f.id = formations.size()
				f.army = army
				f.brigade = b.id
				f.label = "%d/%d" % [k + 1, bi + 1]
				f.ranks = 3 if army == 0 else 2
				f.max_strength = men
				f.strength = men
				f.facing = yaw
				f.prev_facing = yaw
				f.ftype = T.COLUMN
				f.ftype_from = T.COLUMN
				f.pos = Vector2(bx, bz) + right * (k - (per_brigade - 1) * 0.5) * 120.0
				f.prev_pos = f.pos
				f.refresh_shape()
				f.next_fire = rng.randf_range(0.0, 10.0)
				b.battalions.append(f)
				formations.append(f)
				made += 1
			# Opening orders, delivered before the battle: first line deploys forward,
			# second line follows in column, the rest wait in reserve.
			if row <= 1:
				var dest := Vector2(bx, sgn * (160.0 if row == 0 else 400.0))
				var o := make_order(b, dest, yaw, T.LINE if row == 0 else T.COLUMN)
				o.status = "staff"
				o.delivered = 0.0
				o.exec_at = rng.randf_range(0.0, 30.0)
				b.pending.append(o)


func make_order(b, dest: Vector2, facing: float, ftype: int) -> Dictionary:
	_order_id += 1
	return {
		"id": _order_id, "army": b.army, "brigade": b.id, "dest": dest, "facing": facing,
		"ftype": ftype, "issued": time, "delivered": -1.0, "exec_at": -1.0, "status": "riding",
	}


## Called by a courier when it reaches the brigade commander.
func deliver_order(o: Dictionary) -> void:
	var b = brigades[o.brigade]
	o.status = "staff"
	o.delivered = time
	# Staff work: reading, deciding, passing it down to battalions.
	o.exec_at = time + rng.randf_range(20.0, 75.0)
	b.pending.append(o)
	b.awaiting = false


func order_lost(o: Dictionary) -> void:
	o.status = "lost"
	brigades[o.brigade].awaiting = false


# ---------------------------------------------------------------- stepping

func advance(dt: float) -> void:
	accum += dt
	var guard := 0
	while accum >= TICK and guard < 400:
		accum -= TICK
		guard += 1
		_tick()


## Render interpolation factor between the previous and current tick.
func alpha() -> float:
	return clampf(accum / TICK, 0.0, 1.0)


func _tick() -> void:
	time += TICK
	tick_count += 1
	_process_orders()
	_apply_hits()
	for f: Formation in formations:
		_move(f, TICK)
	# Broad-phase work at 2 Hz: battalions move < 1.5 m per tick, cells are 300 m.
	if tick_count % 5 == 0:
		_rebuild_grid()
	if tick_count % 10 == 0:
		_separate()
		_update_slopes()
		_combat(1.0)
		_ai()


## Uphill slows a battalion; sampled at 1 Hz rather than every tick.
func _update_slopes() -> void:
	for f: Formation in formations:
		if f.dead or not f.has_target:
			continue
		var dir := (f.target_pos - f.pos).normalized()
		var here: float = terrain.height(f.pos.x, f.pos.y)
		var ahead: float = terrain.height(f.pos.x + dir.x * 10.0, f.pos.y + dir.y * 10.0)
		f.slope_factor = clampf(1.0 - (ahead - here) * 0.4, 0.5, 1.15)


func _rebuild_grid() -> void:
	_grid.clear()
	for f: Formation in formations:
		if f.dead:
			continue
		f.cpos = f.center()
		var key := Vector2i(floori(f.pos.x / CELL), floori(f.pos.y / CELL))
		if _grid.has(key):
			_grid[key].append(f)
		else:
			_grid[key] = [f]


func neighbours(p: Vector2) -> Array:
	var out := []
	var cx := floori(p.x / CELL)
	var cz := floori(p.y / CELL)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell = _grid.get(Vector2i(cx + dx, cz + dz))
			if cell != null:
				out.append_array(cell)
	return out


func nearest_enemy(p: Vector2, army: int, radius: float):
	var best = null
	var bd := radius * radius
	for e: Formation in neighbours(p):
		if e.army == army:
			continue
		var d2: float = e.cpos.distance_squared_to(p)
		if d2 < bd:
			bd = d2
			best = e
	return best


func _process_orders() -> void:
	for b in brigades:
		if b.pending.is_empty():
			continue
		for o in b.pending.duplicate():
			if time >= o.exec_at:
				b.pending.erase(o)
				_apply_order(b, o)


func _apply_order(b, o: Dictionary) -> void:
	var bns: Array = b.alive()
	if bns.is_empty():
		return
	var ft: int = o.ftype
	var facing: float = o.facing
	var right := Vector2(cos(facing), -sin(facing))
	bns.sort_custom(func(a, c): return a.pos.dot(right) < c.pos.dot(right))
	var gap := 35.0 if ft == T.LINE else 80.0
	var widths := []
	var total := gap * (bns.size() - 1)
	for f in bns:
		var w: float = Formation.footprint_for(ft, f.strength, f.ranks).x
		widths.append(w)
		total += w
	var x := -total * 0.5
	for k in bns.size():
		var f = bns[k]
		if f.routing:
			continue
		f.target_pos = o.dest + right * (x + widths[k] * 0.5)
		x += widths[k] + gap
		f.target_facing = facing
		f.target_ftype = ft
		f.has_target = true
		var far: bool = f.pos.distance_to(f.target_pos) > 300.0
		f.march_ftype = T.COLUMN if far and ft != T.MARCH else ft
	if b.current != null and b.current.status == "executing":
		b.current.status = "superseded"
	o.status = "executing"
	b.current = o


func _move(f: Formation, dt: float) -> void:
	f.prev_pos = f.pos
	f.prev_facing = f.facing
	if f.dead:
		return
	var was_moving: bool = f.moving
	# Fast path: most battalions are standing still at any moment.
	if not f.has_target and not f.routing and f.rout_amount == 0.0:
		if was_moving:
			f.moving = false
			f.render_dirty = true
		return
	f.moving = false

	var target_rout := 1.0 if f.routing else 0.0
	if f.rout_amount != target_rout:
		f.rout_amount = move_toward(f.rout_amount, target_rout, dt / (8.0 if f.routing else 15.0))
		f.render_dirty = true

	if f.routing:
		f.pos += f.back() * f.speed() * dt
		f.moving = true
	elif f.is_transitioning(time):
		pass
	elif f.has_target:
		var to: Vector2 = f.target_pos - f.pos
		var dist := to.length()
		var maxturn: float = f.turn_rate() * dt
		if dist > 3.0:
			var threat: Vector2 = f.threat_dir
			if f.ftype != f.march_ftype and dist > 20.0:
				f.begin_transition(f.march_ftype, time)
			elif f.engaged and to.dot(threat) > 0.0:
				pass # under fire: halt and return fire rather than press on
			else:
				var sidestep: bool = f.ftype == T.LINE and dist < 60.0
				var want: float = f.target_facing if sidestep else atan2(-to.x, -to.y)
				var diff := angle_difference(f.facing, want)
				f.facing += clampf(diff, -maxturn, maxturn)
				f.moving = true
				if absf(diff) < 0.5 or sidestep:
					f.pos += to / dist * minf(f.speed() * f.slope_factor * dt, dist)
		elif f.ftype != f.target_ftype:
			f.begin_transition(f.target_ftype, time)
		else:
			var diff := angle_difference(f.facing, f.target_facing)
			if absf(diff) > 0.01:
				f.facing += clampf(diff, -maxturn, maxturn)
				f.moving = true
			else:
				f.has_target = false

	f.pos = f.pos.clamp(Vector2(-MAP_LIMIT, -MAP_LIMIT), Vector2(MAP_LIMIT, MAP_LIMIT))
	if f.moving != was_moving:
		f.render_dirty = true


func _separate() -> void:
	for f: Formation in formations:
		if f.dead:
			continue
		var c: Vector2 = f.cpos
		var rf: float = f.fp.x * 0.5 + 5.0
		var cx := floori(f.pos.x / CELL)
		var cz := floori(f.pos.y / CELL)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell = _grid.get(Vector2i(cx + dx, cz + dz))
				if cell == null:
					continue
				for e: Formation in cell:
					if e.id <= f.id:
						continue
					var ce: Vector2 = e.cpos
					var d := c.distance_to(ce)
					var min_d := (rf + e.fp.x * 0.5 + 5.0) * 0.7
					if d < min_d and d > 0.01:
						var push := (c - ce) / d * (min_d - d) * 0.3
						f.pos += push
						e.pos -= push


func _combat(dt: float) -> void:
	for f: Formation in formations:
		if f.dead:
			continue
		f.engaged = false
		var c: Vector2 = f.cpos
		var e: Formation = nearest_enemy(c, f.army, 360.0)
		if f.routing:
			if f.broken:
				if time > f.broken_at + 90.0:
					f.dead = true
					f.render_dirty = true
				continue
			if e == null:
				f.morale += 0.02 * dt
			if f.morale > 0.55:
				f.routing = false
				f.has_target = false
				f.begin_transition(T.LINE, time)
			continue
		if e == null:
			f.morale = minf(1.0, f.morale + 0.004 * dt)
			continue
		var to: Vector2 = e.cpos - c
		var d := to.length()
		if d > FIRE_RANGE:
			f.morale = minf(1.0, f.morale + 0.002 * dt)
			continue
		f.engaged = true
		f.threat_dir = to / maxf(d, 0.1)
		var trans: bool = f.is_transitioning(time)
		if f.ftype == T.MARCH and not trans:
			f.begin_transition(T.LINE, time)
			continue
		var can_bear: bool = f.ftype == T.SQUARE or absf(f.forward().angle_to(to)) < deg_to_rad(65.0)
		if not can_bear and not trans and not f.has_target:
			f.target_pos = f.pos
			f.target_facing = atan2(-to.x, -to.y)
			f.target_ftype = f.ftype
			f.march_ftype = f.ftype
			f.has_target = true
		if can_bear and not trans and not f.moving and time >= f.next_fire:
			_volley(f, e, d)


func _volley(f: Formation, e: Formation, d: float) -> void:
	var p: float = 0.2 * exp(-d / 70.0) * (0.6 + 0.4 * f.morale)
	var cas := int(round(f.firing_muskets() * p * rng.randf_range(0.6, 1.4)))
	if e.ftype == T.COLUMN or e.ftype == T.SQUARE:
		cas = int(cas * 1.3)
	f.last_volley = time + 1.6
	f.next_fire = time + rng.randf_range(18.0, 26.0)
	f.render_dirty = true
	events.append({"type": "volley", "f": f, "t": f.last_volley})
	if cas > 0:
		_hits.append([f.last_volley + 0.2, e, cas])


func _apply_hits() -> void:
	if _hits.is_empty():
		return
	var keep := []
	for h in _hits:
		if time < h[0]:
			keep.append(h)
			continue
		var e = h[1]
		if e.dead:
			continue
		var cas: int = mini(h[2], e.strength)
		e.strength -= cas
		e.refresh_shape()
		e.morale -= float(cas) / e.max_strength * 5.0 + 0.015
		e.render_dirty = true
		events.append({"type": "casualties", "f": e, "n": cas})
		if e.strength < e.max_strength * 0.15 and not e.broken:
			e.broken = true
			e.broken_at = time
			_start_rout(e)
		elif e.morale < 0.25 and not e.routing:
			_start_rout(e)
	_hits = keep


func _start_rout(f: Formation) -> void:
	f.routing = true
	f.has_target = false
	f.render_dirty = true
	events.append({"type": "rout", "f": f})
	# Panic is contagious.
	for n in neighbours(f.cpos):
		if n.army == f.army and n != f and n.cpos.distance_to(f.cpos) < 300.0:
			n.morale -= 0.08


# ---------------------------------------------------------------- AI

func _ai() -> void:
	for b in brigades:
		if not ai_enabled[b.army] or time < b.ai_next or b.awaiting:
			continue
		b.ai_next = time + rng.randf_range(90.0, 150.0)
		if b.alive().is_empty() or (b.row >= 2 and time < b.row * 240.0):
			continue
		var c: Vector2 = b.centroid()
		var target = null
		var bd := INF
		for ob in brigades:
			if ob.army == b.army or ob.alive().is_empty():
				continue
			var d: float = ob.centroid().distance_to(c)
			if d < bd:
				bd = d
				target = ob
		if target == null:
			continue
		var to: Vector2 = target.centroid() - c
		var dir := to.normalized()
		var facing := atan2(-dir.x, -dir.y)
		var o: Dictionary
		if bd > 900.0:
			o = make_order(b, c + dir * 450.0, facing, T.COLUMN)
		else:
			o = make_order(b, target.centroid() - dir * 120.0, facing, T.LINE if rng.randf() < 0.75 else T.COLUMN)
		b.awaiting = true
		if order_sink.is_valid():
			order_sink.call(o)
		else:
			deliver_order(o)


## Stress helper: every battalion changes formation at once.
func chaos() -> void:
	for f in formations:
		if f.dead or f.routing:
			continue
		var choices := [T.LINE, T.COLUMN, T.SQUARE, T.MARCH]
		choices.erase(f.ftype)
		f.has_target = false
		f.begin_transition(choices[rng.randi() % choices.size()], time)


func soldiers_alive(army := -1) -> int:
	var n := 0
	for f in formations:
		if not f.dead and (army < 0 or f.army == army):
			n += f.strength
	return n
