extends RefCounted
## Formation-level battle simulation. Fixed 10 Hz tick, independent of frame
## rate (needed for time compression). Nothing here scales with the number of
## men, only with the number of battalions.

const Formation = preload("res://src/formation.gd")
const Command = preload("res://src/command.gd")
const Brigade = preload("res://src/brigade.gd")
const OobNames = preload("res://src/oob_names.gd")
const Orientation = preload("res://src/orientation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const BrigadeBrain = preload("res://src/ai/brigade_brain.gd")
const T := Formation.Type

const TICK := 0.1
const CELL := 300.0
const FIRE_RANGE := 180.0
const MAP_LIMIT := 2900.0
## Companies per battalion: French 6 (from 1808), British 10.
const COMPANIES := [6, 10]
## Interval between battalions side by side (15.6 m in the French drill).
const BN_INTERVAL := 15.6
## Order of battle: brigades per division, divisions per corps.
const BRIGADES_PER_DIVISION := 2
const DIVISIONS_PER_CORPS := 4


var terrain
var formations: Array = []
var brigades: Array = []
## Top of each army's chain of command (Command, level ARMY), by army index.
var armies: Array = [null, null]
var names: OobNames
var _regiment := [0, 0]
## Sim time is a pure function of the tick count, so it never drifts and the
## same ticks give the same battle whatever the frame rate.
var time := 0.0
var accum := 0.0
var tick_count := 0
var events: Array = []
var ai_enabled := [false, true]
var hq := [Vector2.ZERO, Vector2.ZERO]
## Callable(army: int) -> Vector2: where an army's orders are written (the
## player's are written wherever the general is). Defaults to `hq`.
var order_origin: Callable
var couriers: Array = []
var couriers_delivered := 0
var couriers_lost := 0
## Per-phase microseconds of _tick, filled when `profile` is on (sim_profile.gd).
var profile := false
var phase_usec := {}
var _grid := {}
var _hits: Array = []
var _order_id := 0
## Commands with orders waiting out their staff work.
var _mail: Array = []
## Every random draw in the sim comes from here, in tick order: determinism.
var rng := RandomNumberGenerator.new()
var _personality_rng := RandomNumberGenerator.new()


## A rider carrying an order. He rides to wherever the recipient's commander is
## *now*, can be shot riding past the enemy, and rides home afterwards.
class Courier:
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var home := Vector2.ZERO
	var army := 0
	var order
	var target := Vector2.ZERO
	var returning := false
	var hazard_t := 1.0  # re-aim and run the gauntlet on the first tick


const COURIER_SPEED := 6.5  # m/s, a hard canter over broken ground (~23 km/h)
const COURIER_HAZARD_RADIUS := 140.0
const COURIER_HAZARD_PER_SEC := 0.03


func _init(t) -> void:
	terrain = t
	rng.seed = 1815
	_personality_rng.seed = 1769
	names = OobNames.new(1815)


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
			var b := _add_brigade(army, row)
			for k in per_brigade:
				if made >= bns_per_side:
					break
				var p := Vector2(bx, bz) + right * (k - (per_brigade - 1) * 0.5) * 120.0
				_add_battalion(b, men, p, yaw, T.COLUMN)
				made += 1
			# Opening orders, delivered before the battle: first line deploys forward,
			# second line follows in column, the rest wait in reserve.
			if row <= 1:
				var dest := Vector2(bx, sgn * (160.0 if row == 0 else 400.0))
				var o := make_order(b, dest, T.LINE if row == 0 else T.COLUMN, yaw)
				_hand_over(o, rng.randf_range(0.0, 30.0))
		_organise(army)


## Small engagement: one brigade per side in line, `gap` metres apart (front
## rank to front rank) around `site`. The French brigade is already advancing
## on the Allied line, which stands and waits. Neither side has an AI general.
func deploy_contact(site: Vector2, men: int, gap: float) -> void:
	for army in 2:
		var yaw := 0.0 if army == 0 else PI
		var right := Vector2(cos(yaw), -sin(yaw))
		var front := Vector2(site.x, site.y + gap * (0.5 if army == 0 else -0.5))
		var b := _add_brigade(army, 0)
		var ranks := 3 if army == 0 else 2
		var w: float = Formation.footprint_for(T.LINE, men, ranks, COMPANIES[army]).x
		var total := 4.0 * w + 3.0 * BN_INTERVAL
		for k in 4:
			var p := front + right * (-total * 0.5 + w * 0.5 + k * (w + BN_INTERVAL))
			_add_battalion(b, men, p, yaw, T.LINE)
		hq[army] = front + Vector2(0, 600.0 if army == 0 else -600.0)
		_organise(army)
	# Advance to 60 m short of the enemy line: close enough to stay in line
	# (no column for the march) and the halt-and-fire SOP stops them at musket range.
	_hand_over(make_order(brigades[0], Vector2(site.x, site.y - gap * 0.5 + 60.0), T.LINE, 0.0), 0.0)
	ai_enabled = [false, false]


## Corps Command (map "hill"): a French corps of four divisions facing an
## Anglo-Allied corps of two on the ridge to the north, everyone halted. Drawn up
## in the usual manner of the period:
##   1st Division  first line: both brigades deployed in line
##   2nd Division  second line, ~220 m behind: battalion columns at deploying
##                 distance, posted behind the intervals of the first line (shifted
##                 71 m, half a battalion's frontage plus half an interval) so
##                 they can pass through it
##   3rd, 4th Div  in route column on two roads to the rear, either side of the hill
## The enemy holds the crest in line, his second division in columns on the
## reverse slope, out of sight. Positions are the centre of each brigade's front
## (the head of a march column); facing north is yaw 0.
const CORPS_SETUP := [
	[[Vector2(-286, 250), T.LINE], [Vector2(286, 250), T.LINE],
	[Vector2(-215, 470), T.COLUMN], [Vector2(357, 470), T.COLUMN],
	[Vector2(-760, 1150), T.MARCH], [Vector2(-760, 1700), T.MARCH],
	[Vector2(700, 1150), T.MARCH], [Vector2(700, 1700), T.MARCH]],
	[[Vector2(406, -880), T.LINE], [Vector2(-406, -880), T.LINE],
	[Vector2(406, -1180), T.COLUMN], [Vector2(-406, -1180), T.COLUMN]],
]
const CORPS_HQ := [Vector2(-250, 950), Vector2(0, -1600)]


func deploy_corps(men: int) -> void:
	for army in 2:
		var yaw := 0.0 if army == 0 else PI
		for spec in CORPS_SETUP[army]:
			var b := _add_brigade(army, 0)
			for k in 4:
				_add_battalion(b, men, spec[0], yaw, spec[1])
			var slots := _brigade_slots(b.battalions, spec[0], yaw, spec[1])
			for k in slots.size():
				b.battalions[k].pos = slots[k]
				b.battalions[k].prev_pos = slots[k]
		hq[army] = CORPS_HQ[army]
		_organise(army)
	ai_enabled = [false, false]


## Brigades are named after their général, as was the custom.
func _add_brigade(army: int, row: int) -> Brigade:
	var b := Brigade.new()
	b.id = brigades.size()
	b.army = army
	b.row = row
	var surname := names.surname(army)
	b.commander = "%s %s" % [OobNames.RANKS[army][Command.Level.BRIGADE], surname]
	var n := OobNames.brigade_names(army, surname)
	b.title = n[0]
	b.label = n[1]
	b.ai_next = rng.randf_range(20.0, 120.0)
	b.roll_personality(_personality_rng)
	brigades.append(b)
	return b


## French brigades are two regiments of two battalions; British brigades are
## single battalions of different regiments. Light brigades match the
## renderer's palette (FormationRenderer.palette).
func _add_battalion(b: Brigade, men: int, p: Vector2, yaw: float, ftype: int) -> Formation:
	var k := b.battalions.size()
	var light := (b.id % 7 == 5) if b.army == 0 else (b.id % 9 == 4)
	var bn := k % 2 + 1
	if b.army == 1:
		bn = 1 + names.rng.randi() % 2
	if b.army == 1 or k % 2 == 0:
		_regiment[b.army] += 1 + names.rng.randi() % 3
	var f := Formation.new()
	f.id = formations.size()
	f.army = b.army
	f.brigade = b.id
	var n := OobNames.battalion_names(b.army, _regiment[b.army], bn, light)
	f.title = n[0]
	f.label = n[1]
	f.commander = names.commander(b.army, 4)
	f.ranks = 3 if b.army == 0 else 2
	f.companies = COMPANIES[b.army]
	f.max_strength = men
	f.strength = men
	f.facing = yaw
	f.prev_facing = yaw
	f.ftype = ftype
	f.ftype_from = ftype
	f.pos = p
	f.prev_pos = p
	f.refresh_shape()
	f.next_fire = rng.randf_range(0.0, 10.0)
	f.roll_personality(_personality_rng)
	b.add_battalion(f)
	formations.append(f)
	return f


## Builds the chain of command above one army's brigades: army > corps >
## division > brigade. Brigades are in deployment order, so neighbours share a
## division and divisions in the same part of the field share a corps.
func _organise(army: int) -> void:
	var a := Command.new()
	a.level = Command.Level.ARMY
	a.army = army
	a.title = OobNames.ARMY_TITLES[army]
	a.label = a.title
	a.commander = names.commander(army, Command.Level.ARMY)
	a.roll_personality(_personality_rng)
	armies[army] = a
	var corps = null
	var division = null
	var n_div := 0
	var n_corps := 0
	for b in brigades:
		if b.army != army:
			continue
		if division == null or division.subordinates.size() >= BRIGADES_PER_DIVISION:
			if corps == null or corps.subordinates.size() >= DIVISIONS_PER_CORPS:
				n_corps += 1
				corps = _add_command(a, Command.Level.CORPS, OobNames.corps_title(army, n_corps))
			n_div += 1
			division = _add_command(corps, Command.Level.DIVISION, OobNames.division_title(army, n_div))
		division.add(b)
		# Orders handed over before the battle came from army headquarters.
		for o in b.inbox:
			o.issuer = a


func _add_command(parent, level: int, title: String):
	var c := Command.new()
	c.level = level
	c.army = parent.army
	c.title = title
	c.label = title
	c.commander = names.commander(parent.army, level)
	c.roll_personality(_personality_rng)
	parent.add(c)
	return c


## A blank order from `issuer` (null: the player) to `recipient`.
func new_order(recipient, kind: int, objective, issuer = null) -> Order:
	_order_id += 1
	var o := Order.new()
	o.id = _order_id
	o.army = recipient.army
	o.recipient = recipient
	o.issuer = issuer
	o.kind = kind
	o.objective = objective
	o.issued = time
	return o


## Go to `dest` and form `ftype` there. `facing` is normally left null: the
## recipient decides its own front when it acts (Orientation). Scripted
## openings may still fix it.
func make_order(recipient, dest: Vector2, ftype: int, facing = null, issuer = null) -> Order:
	var o := new_order(recipient, Order.Kind.MOVE, Objective.point(dest), issuer)
	o.ftype = ftype
	o.facing = facing
	return o


## Send an order by courier from `origin`.
func send_order(o: Order, origin: Vector2) -> void:
	var c := Courier.new()
	c.pos = origin
	c.prev_pos = origin
	c.home = origin
	c.army = o.army
	c.order = o
	couriers.append(c)
	o.recipient.awaiting = true
	_set_status(o, Order.Status.RIDING)


## Where `army`'s orders are written.
func origin_of(army: int) -> Vector2:
	return order_origin.call(army) if order_origin.is_valid() else hq[army]


## The order reaches the recipient's commander: staff work begins.
func deliver_order(o: Order) -> void:
	var cmd = o.recipient
	o.delivered = time
	o.exec_at = time + cmd.staff_delay(rng)
	_queue(o)
	_set_status(o, Order.Status.PREPARING)
	events.append({"type": "order_delivered", "o": o})


## An order already in the recipient's hands before the battle, acted on at `at`.
func _hand_over(o: Order, at: float) -> void:
	o.delivered = 0.0
	o.exec_at = at
	o.status = Order.Status.PREPARING
	_queue(o)


func _queue(o: Order) -> void:
	var cmd = o.recipient
	cmd.inbox.append(o)
	cmd.awaiting = false
	if not _mail.has(cmd):
		_mail.append(cmd)


func order_lost(o: Order) -> void:
	o.recipient.awaiting = false
	_set_status(o, Order.Status.LOST)
	events.append({"type": "order_lost", "o": o})


## Every status change goes through here, so the UI can follow by events.
func _set_status(o: Order, s: int) -> void:
	o.status = s
	if s >= Order.Status.COMPLETE:
		o.finished = time
	events.append({"type": "order_status", "o": o})


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


## Per-tick work at 10 Hz. The 1 Hz work (separation, slopes, musketry and
## morale, commanders) is staggered: each tick takes the units whose id falls in
## that tick's tenth, so no single tick carries it all.
func _tick() -> void:
	tick_count += 1
	time = tick_count * TICK
	var slot := tick_count % 10
	var t := _now_usec()
	_process_orders()
	t = _prof("orders", t)
	_step_couriers(TICK)
	t = _prof("couriers", t)
	_apply_hits()
	t = _prof("hits", t)
	for f: Formation in formations:
		_move(f, TICK)
	t = _prof("move", t)
	# Broad-phase work at 2 Hz: battalions move < 1.5 m per tick, cells are 300 m.
	if tick_count % 5 == 0:
		_rebuild_grid()
		t = _prof("grid (2 Hz)", t)
	_separate(slot)
	t = _prof("separate (1 Hz)", t)
	_update_slopes(slot)
	t = _prof("slopes (1 Hz)", t)
	_combat(slot, 1.0)
	t = _prof("combat (1 Hz)", t)
	_ai(slot)
	for b in brigades:
		if b.id % 10 == slot:
			BrigadeBrain.think(self, b)
	t = _prof("commanders (1 Hz)", t)


func _now_usec() -> int:
	return Time.get_ticks_usec() if profile else 0


func _prof(phase: String, since: int) -> int:
	if not profile:
		return 0
	var now := Time.get_ticks_usec()
	phase_usec[phase] = phase_usec.get(phase, 0) + now - since
	return now


func _step_couriers(dt: float) -> void:
	if couriers.is_empty():
		return
	for c: Courier in couriers.duplicate():
		c.prev_pos = c.pos
		var o: Order = c.order
		# Once a second: look for the recipient again (he moves), and risk the
		# enemy's fire if riding close past him.
		c.hazard_t += dt
		if c.hazard_t >= 1.0:
			c.hazard_t -= 1.0
			if not c.returning:
				if o.recipient.is_gone():
					order_lost(o)
					c.returning = true
				else:
					c.target = o.recipient.position()
			if nearest_enemy(c.pos, c.army, COURIER_HAZARD_RADIUS) != null and rng.randf() < COURIER_HAZARD_PER_SEC:
				if not c.returning:
					couriers_lost += 1
					order_lost(o)
				couriers.erase(c)
				continue
		var to: Vector2 = (c.home if c.returning else c.target) - c.pos
		var d: float = to.length()
		var step := COURIER_SPEED * dt
		if d <= maxf(step, 12.0):
			if c.returning:
				couriers.erase(c)
				continue
			deliver_order(o)
			couriers_delivered += 1
			c.returning = true
			continue
		c.pos += to / d * step


func riding_count(army: int) -> int:
	var n := 0
	for c: Courier in couriers:
		if c.army == army and not c.returning:
			n += 1
	return n


## Uphill slows a battalion; sampled at 1 Hz rather than every tick.
func _update_slopes(slot: int) -> void:
	for i in range(slot, formations.size(), 10):
		var f: Formation = formations[i]
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


## Orders whose staff work is done are acted on, oldest first.
func _process_orders() -> void:
	if _mail.is_empty():
		return
	for cmd in _mail.duplicate():
		for o: Order in cmd.inbox.duplicate():
			if time >= o.exec_at:
				cmd.inbox.erase(o)
				_execute(cmd, o)
		if cmd.inbox.is_empty():
			_mail.erase(cmd)


## The commander acts on an order: it replaces whatever he was doing.
func _execute(cmd, o: Order) -> void:
	if cmd.is_gone():
		return
	var ok := false
	match cmd.level:
		Command.Level.BRIGADE:
			ok = BrigadeBrain.execute(self, cmd, o)
		_:
			push_warning("No brain yet for %s (level %d): order %d ignored" % [cmd.title, cmd.level, o.id])
	if not ok:
		return
	if cmd.order != null and cmd.order.status == Order.Status.EXECUTING:
		_set_status(cmd.order, Order.Status.SUPERSEDED)
	cmd.order = o
	cmd.detached = o.detached
	_set_status(o, Order.Status.EXECUTING)
	events.append({"type": "order_executing", "o": o})


## The commander reports his order carried out.
func complete_order(cmd) -> void:
	_set_status(cmd.order, Order.Status.COMPLETE)
	cmd.detached = false


## Sorts `bns` left to right across the new front (so no two battalions cross)
## and returns the anchor each one takes, in that order.
func assign_slots(bns: Array, dest: Vector2, facing: float, ft: int) -> Array:
	var right := Vector2(cos(facing), -sin(facing))
	bns.sort_custom(func(a, c): return a.pos.dot(right) < c.pos.dot(right))
	return _brigade_slots(bns, dest, facing, ft)


## Where each battalion of a brigade stands (its anchor) in formation `ft`, with
## `dest` the centre of the brigade's front. Line and columns are abreast; columns
## keep deploying distance (the frontage of the line they would form) so each can
## deploy without crowding its neighbours. A march column is one battalion
## behind another, with `dest` at its head.
func _brigade_slots(bns: Array, dest: Vector2, facing: float, ft: int) -> Array:
	var right := Vector2(cos(facing), -sin(facing))
	var back := Vector2(sin(facing), cos(facing))
	var out := []
	if ft == T.MARCH:
		var depth := 0.0
		for f in bns:
			out.append(dest + back * depth)
			depth += f.footprint_as(T.MARCH).y + 20.0
		return out
	var widths := []
	var total := BN_INTERVAL * (bns.size() - 1)
	for f in bns:
		widths.append(f.footprint_as(T.LINE).x)
		total += widths[-1]
	var x := -total * 0.5
	for k in bns.size():
		out.append(dest + right * (x + widths[k] * 0.5))
		x += widths[k] + BN_INTERVAL
	return out


func _move(f: Formation, dt: float) -> void:
	f.prev_pos = f.pos
	f.prev_facing = f.facing
	if f.dead:
		return
	var was_moving: bool = f.moving
	if f.ftype_from != f.ftype and time > f.trans_start + f.trans_dur + 10.0:
		# Drill finished (with margin for the slowest section): the shader can go
		# back to computing a single formation per man.
		f.ftype_from = f.ftype
		f.render_dirty = true
	# Fast path: most battalions are standing still at any moment.
	if not f.has_target and not f.routing and f.rout_amount == 0.0:
		if was_moving:
			f.moving = false
			f.moving_since = time
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
		f.moving_since = time
		f.render_dirty = true


## Pushes overlapping battalions apart. Each pair is handled once a second, in
## the tick of the lower id.
func _separate(slot: int) -> void:
	for i in range(slot, formations.size(), 10):
		var f: Formation = formations[i]
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


func _combat(slot: int, dt: float) -> void:
	for i in range(slot, formations.size(), 10):
		var f: Formation = formations[i]
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

func _ai(slot: int) -> void:
	for b in brigades:
		if b.id % 10 != slot or not ai_enabled[b.army] or time < b.ai_next or b.awaiting:
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
		var dir: Vector2 = (target.centroid() - c).normalized()
		var o: Order
		if bd > 900.0:
			o = make_order(b, c + dir * 450.0, T.COLUMN, null, armies[b.army])
		else:
			o = make_order(b, target.centroid() - dir * 120.0, T.LINE if rng.randf() < 0.75 else T.COLUMN, null, armies[b.army])
		send_order(o, origin_of(b.army))


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
