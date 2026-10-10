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
const BattalionBrain = preload("res://src/ai/battalion_brain.gd")
const T := Formation.Type
const F := Formation.Fire

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


## Moves to the rear shorter than this are made stepping back, front to the enemy.
const BACKSTEP_DISTANCE := 400.0
## A line whose new front is further off its present one than this wheels to
## it before it moves; nearer, it eases round on the march.
const WHEEL_FIRST := PI / 6.0  # 30 degrees
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


## Small engagement, and the sandbox for orders: one brigade per side in line,
## `gap` metres apart (front rank to front rank) around `site`, both halted.
## The French brigade is the player's, with no orders yet. Each Allied
## battalion has orders to hold its ground. Neither side has an AI general.
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
	for f in brigades[1].battalions:
		var hold := new_order(f, Order.Kind.HOLD, Objective.point(f.pos), brigades[1])
		hold.facing = f.facing  # as they stand, the line dressed
		_hand_over(hold, 0.0)
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
	# Skipping the recipient's own commander detaches it from him until the
	# order is done. The general (the player) commands the army.
	var by = issuer if issuer != null else armies[recipient.army]
	o.detached = recipient.parent != null and by != null and recipient.parent != by
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
	_step_charges()
	t = _prof("hits+charges", t)
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
		f.axis_r = Vector2(cos(f.facing), -sin(f.facing))
		var key := Vector2i(floori(f.pos.x / CELL), floori(f.pos.y / CELL))
		if _grid.has(key):
			_grid[key].append(f)
		else:
			_grid[key] = [f]


## Formations in the grid cells around `p`: the 3x3 block by default (reliable
## to about one cell, 300 m), more rings for longer looks.
func neighbours(p: Vector2, rings := 1) -> Array:
	var out := []
	var cx := floori(p.x / CELL)
	var cz := floori(p.y / CELL)
	for dx in range(-rings, rings + 1):
		for dz in range(-rings, rings + 1):
			var cell = _grid.get(Vector2i(cx + dx, cz + dz))
			if cell != null:
				out.append_array(cell)
	return out


## Nearest enemy within `radius` of `p`; `formed`: ignore skirmishers.
func nearest_enemy(p: Vector2, army: int, radius: float, formed := false):
	scan_enemies(p, army, radius)
	return scan_formed if formed else scan_any


## Results of the last scan_enemies(): nearest formed enemy, nearest of any
## kind, nearest skirmishers.
var scan_formed = null
var scan_any = null
var scan_open = null


## One pass over the grid cells round `p` (no arrays built): sets scan_formed
## and scan_any to the nearest enemy battalion in formation, and the nearest
## enemy of any kind (skirmishers included), within `radius`.
func scan_enemies(p: Vector2, army: int, radius: float) -> void:
	scan_formed = null
	scan_any = null
	scan_open = null
	var bf := radius * radius
	var ba := bf
	var bo := bf
	var rings := 1 if radius <= 360.0 else ceili(radius / CELL)
	var cx := floori(p.x / CELL)
	var cz := floori(p.y / CELL)
	for dx in range(-rings, rings + 1):
		for dz in range(-rings, rings + 1):
			var cell = _grid.get(Vector2i(cx + dx, cz + dz))
			if cell == null:
				continue
			for e: Formation in cell:
				if e.army == army or e.dead:
					continue
				var d2: float = e.cpos.distance_squared_to(p)
				if d2 < ba:
					ba = d2
					scan_any = e
				if e.ftype != T.OPEN:
					if d2 < bf:
						bf = d2
						scan_formed = e
				elif d2 < bo:
					bo = d2
					scan_open = e


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
		Command.Level.BATTALION:
			ok = BattalionBrain.execute(self, cmd, o)
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
	if not f.has_target and not f.routing:
		if was_moving:
			f.moving = false
			f.moving_since = time
			f.render_dirty = true
		return
	f.moving = false

	if f.routing:
		# Back towards the rally point, the men facing about (drawn by the shader).
		var to_rally: Vector2 = f.rally_point - f.pos
		var dr := to_rally.length()
		if dr > 3.0:
			f.pos += to_rally / dr * minf(f.speed() * dt, dr)
			f.moving = true
	elif f.is_transitioning(time) or time < f.obey_at:
		pass
	elif f.has_target:
		var to: Vector2 = f.target_pos - f.pos
		var dist := to.length()
		var maxturn: float = f.turn_rate() * dt
		if dist > 3.0:
			if f.ftype != f.march_ftype and dist > 20.0:
				f.begin_transition(f.march_ftype, time)
			elif f.halted or f.pace_mul <= 0.0:
				pass # halted to give fire, or waiting for the line to come up
			elif _keeps_front(f, to, dist):
				# A line keeps its front: if the new front is well off the old it
				# wheels first, then marches straight to its place, advancing or
				# stepping back in line or, for a lateral shift, by the flank. The
				# men face the way they march (march_dir) and front at the halt.
				# Squares, skirmishers and anyone falling back do the same.
				var turn := angle_difference(f.facing, f.target_facing)
				f.facing += clampf(turn, -maxturn, maxturn)
				f.moving = true
				if f.ftype != T.LINE or absf(turn) <= WHEEL_FIRST:
					var rel := angle_difference(f.facing, atan2(-to.x, -to.y))
					var spd := f.speed()
					if f.ftype == T.LINE and not f.retiring and absf(rel) > PI * 0.25 and absf(rel) < PI * 0.75:
						spd = Formation.QUICK_STEP  # by the flank: files at the quick step
					f.pos += to / dist * minf(spd * f.slope_factor * f.pace_mul * dt, dist)
					_set_march_dir(f, rel)
			else:
				# Columns: the head leads, turning the way it goes.
				var diff := angle_difference(f.facing, atan2(-to.x, -to.y))
				f.facing += clampf(diff, -maxturn, maxturn)
				f.moving = true
				_set_march_dir(f, 0.0)
				if absf(diff) < 0.5:
					f.pos += to / dist * minf(f.speed() * f.slope_factor * f.pace_mul * dt, dist)
		elif f.ftype != f.target_ftype:
			f.begin_transition(f.target_ftype, time)
		else:
			var diff := angle_difference(f.facing, f.target_facing)
			if absf(diff) > 0.01:
				f.facing += clampf(diff, -maxturn, maxturn)
				f.moving = true
			else:
				f.has_target = false
				f.retiring = false

	f.pos = f.pos.clamp(Vector2(-MAP_LIMIT, -MAP_LIMIT), Vector2(MAP_LIMIT, MAP_LIMIT))
	if f.moving != was_moving:
		f.moving_since = time
		f.render_dirty = true


## Does the unit march keeping its front (rather than turning its head to the
## way it goes, as a column does)? Lines, squares and skirmishers always; any
## battalion falling back; and a column going a short way to the rear, which
## faces about rather than countermarching.
func _keeps_front(f: Formation, to: Vector2, dist: float) -> bool:
	match f.ftype:
		T.LINE, T.SQUARE, T.OPEN:
			return true
		T.MARCH:
			return f.retiring
	return f.retiring or (dist < BACKSTEP_DISTANCE and to.dot(f.forward()) < -0.5 * dist)


## Which way the men face while marching, relative to the front (the shader
## turns them). A formed battalion faces by the drill: front, right or left
## face, or about face. Skirmishers just face the way they run.
func _set_march_dir(f: Formation, rel: float) -> void:
	var q: float
	if f.ftype == T.OPEN:
		q = snappedf(rel, PI / 12.0)
	elif absf(rel) <= PI * 0.25:
		q = 0.0
	elif absf(rel) >= PI * 0.75:
		q = PI
	else:
		q = signf(rel) * PI * 0.5
	if q != f.march_dir:
		f.march_dir = q
		f.render_dirty = true


## Pushes overlapping battalions apart. Each pair is handled once a second, in
## the tick of the lower id.
func _separate(slot: int) -> void:
	for i in range(slot, formations.size(), 10):
		var f: Formation = formations[i]
		if f.dead or f.ftype == T.OPEN:
			continue  # skirmishers go where they please
		var c: Vector2 = f.cpos
		var fr: Vector2 = f.axis_r
		var ff := Vector2(-fr.y, fr.x)  # perpendicular: the front-to-back axis
		var rf: float = f.fp_radius
		var cx := floori(f.pos.x / CELL)
		var cz := floori(f.pos.y / CELL)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell = _grid.get(Vector2i(cx + dx, cz + dz))
				if cell == null:
					continue
				for e: Formation in cell:
					if e.id <= f.id or e.ftype == T.OPEN or (e.army != f.army and (f.charge != null or e.charge != null)):
						continue  # a charge is meant to close
					var ce: Vector2 = e.cpos
					var d := c.distance_to(ce)
					if d > (rf + e.fp_radius) * 0.85 or d < 0.01:
						continue
					# Each footprint's half-extent towards the other (an oriented box,
					# so lines side by side keep their interval and opposing lines can
					# close front to front).
					var u := (c - ce) / d
					var er: Vector2 = e.axis_r
					var ef := Vector2(-er.y, er.x)
					var ext_f := absf(u.dot(fr)) * f.fp.x * 0.5 + absf(u.dot(ff)) * f.fp.y * 0.5
					var ext_e := absf(u.dot(er)) * e.fp.x * 0.5 + absf(u.dot(ef)) * e.fp.y * 0.5
					var min_d := (ext_f + ext_e) * 0.85
					if d < min_d:
						var push := u * (min_d - d) * 0.3
						f.pos += push
						e.pos -= push


## Standing orders, musketry and morale: each battalion's brain, once a second.
func _combat(slot: int, dt: float) -> void:
	for i in range(slot, formations.size(), 10):
		var f: Formation = formations[i]
		if not f.dead:
			BattalionBrain.think(self, f, dt)


## Chance that one musket fired at `d` metres hits, before the manner of fire.
func hit_chance(f: Formation, e: Formation, d: float) -> float:
	var p: float = 0.2 * exp(-d / 70.0) * (0.6 + 0.4 * f.morale)
	if e.ftype == T.COLUMN or e.ftype == T.SQUARE:
		p *= 1.3  # deep targets: every ball finds someone
	elif e.ftype == T.OPEN:
		p *= 0.3  # men a few paces apart, in what cover they find
	return p


## The whole battalion fires at the word of command.
func volley(f: Formation, e: Formation, d: float) -> void:
	var cas := int(round(f.firing_muskets() * hit_chance(f, e, d) * rng.randf_range(0.6, 1.4)))
	f.last_volley = time + 1.6
	f.last_shot = f.last_volley
	f.next_fire = time + rng.randf_range(18.0, 26.0)
	f.render_dirty = true
	events.append({"type": "volley", "f": f, "t": f.last_volley})
	if cas > 0:
		_hits.append([f.last_volley + 0.2, e, cas, BattalionBrain.SHOCK[F.VOLLEY], 1.0])


## Continuous fire between t0 and t1. By platoon: companies fire in turn,
## rolling from the right, one every PLATOON_CYCLE / companies seconds; the
## shader draws the same schedule from fire_start. At will: each man on his own
## cycle, so the battalion's fire is a steady patter.
func continuous_fire(f: Formation, e: Formation, d: float, t0: float, t1: float) -> void:
	var p: float = hit_chance(f, e, d) * BattalionBrain.ACCURACY[f.fire_now]
	var shock: float = BattalionBrain.SHOCK[f.fire_now]
	if f.is_skirmisher and e.ftype != T.OPEN:
		shock *= SKIRMISH_SHOCK  # they pick off the officers and file-closers
	var c: int = f.companies
	if f.fire_now == F.PLATOON:
		var step := Formation.PLATOON_CYCLE / c
		var n := maxi(ceili((t0 - f.fire_start) / step), 0)
		while f.fire_start + n * step < t1:
			var ts := f.fire_start + n * step
			var k := c - 1 - n % c
			n += 1
			if f.company_absent(k):
				continue
			f.cas_accum += float(f.firing_muskets()) / c * p * rng.randf_range(0.6, 1.4)
			_owe_hits(f, e, ts + 0.2, shock, 1.0 / c)
			events.append({"type": "fire", "f": f, "k": k, "t": ts})
			f.last_shot = ts
	elif f.fire_now == F.AT_WILL and t1 > f.fire_start:
		var span := minf(t1 - maxf(t0, f.fire_start), t1 - t0)
		var share := span / Formation.AT_WILL_CYCLE
		f.cas_accum += f.firing_muskets() * share * p * rng.randf_range(0.6, 1.4)
		_owe_hits(f, e, t1, shock, share)
		events.append({"type": "fire", "f": f, "k": -1, "t": t0})
		f.last_shot = t1


## Skirmish fire on formed troops shakes them more per man hit.
const SKIRMISH_SHOCK := 1.5


## Would `f` fire through its own side's skirmishers to hit `e` at `d`? True if
## any are between them, across the line of fire.
func masked(f: Formation, e: Formation, d: float) -> bool:
	var dir := (e.cpos - f.cpos) / maxf(d, 0.1)
	var side := dir.orthogonal()
	for s: Formation in neighbours(f.cpos):
		if s.army != f.army or s.ftype != T.OPEN or s.dead:
			continue
		var v: Vector2 = s.pos - f.cpos
		var along := v.dot(dir)
		if along <= 0.0 or along >= d - 5.0:
			continue
		if absf(v.dot(side)) < (s.fp.x + f.fp.x) * 0.4:
			return true
	return false


## Pays the whole casualties out of the fractional account, so small companies
## and single seconds of fire still add up exactly.
func _owe_hits(f: Formation, e: Formation, at: float, shock: float, share: float) -> void:
	var cas := int(f.cas_accum)
	f.cas_accum -= cas
	if cas > 0 or share > 0.0:
		_hits.append([at, e, cas, shock, share])


## Hits land: [time, target, casualties, shock, share of a full volley].
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
		var shock: float = h[3]
		if e.activity == Formation.Activity.CHARGING:
			shock *= CHARGE_ELAN  # going in with the bayonet, men press on through it
		if cas > 0:
			e.strength -= cas
			e.refresh_shape()
			e.render_dirty = true
			events.append({"type": "casualties", "f": e, "n": cas})
		# Losses shake men; so does the noise of fire coming their way.
		e.morale -= (float(cas) / e.max_strength * 5.0 + 0.015 * h[4]) * shock
		if e.strength < e.max_strength * 0.15 and not e.broken:
			e.broken_at = time
			_start_rout(e, true)
		elif e.morale < 0.25 and not e.routing:
			_start_rout(e)
	_hits = keep


func _start_rout(f: Formation, broken := false) -> void:
	f.set_morale_state(Formation.Morale.BROKEN if broken else Formation.Morale.ROUTING, time)
	f.has_target = false
	f.halted = false
	f.retiring = false
	f.activity = Formation.Activity.IDLE
	BattalionBrain.cease_fire(self, f)
	if f.charge != null:
		events.append({"type": "charge_result", "f": f, "target": f.charge.defender, "result": "faltered"})
		_end_charge(f.charge)
	if f.order != null and f.order.status == Order.Status.EXECUTING and f.order.kind == Order.Kind.ATTACK:
		_set_status(f.order, Order.Status.FAILED)
	f.routed_at = time
	# Run from the danger, to re-form some way back; a battalion that has run
	# once is never quite as steady again.
	var away: Vector2 = -f.threat_dir if f.threat_dir != Vector2.ZERO else f.back()
	f.rally_point = (f.pos + away * BattalionBrain.RALLY_DISTANCE).clamp(Vector2(-MAP_LIMIT, -MAP_LIMIT), Vector2(MAP_LIMIT, MAP_LIMIT))
	f.morale_cap = maxf(0.4, minf(f.morale_cap, 0.75) - 0.15)
	events.append({"type": "rout", "f": f})
	# Panic is contagious (between formed battalions: skirmishers are expected
	# to fall back, and are not watched for it).
	if f.is_skirmisher:
		return
	for n in neighbours(f.cpos):
		if n.army == f.army and n != f and not n.is_skirmisher and n.cpos.distance_to(f.cpos) < 300.0:
			n.morale -= 0.08


## Throws out (or calls in) the battalion's light company as a skirmish screen.
## Out: the company (company 0, the left flank) leaves as a Formation of its
## own in open order and runs out ahead; the battalion keeps its place in the
## ranks. In: it runs back and is absorbed, with whoever is left of it.
func set_skirmishers(f: Formation, out: bool) -> void:
	if not out:
		if f.skirmishers != null:
			f.skirmishers.recalled = true
		return
	if f.skirmishers != null or f.is_skirmisher or f.dead or f.routing or f.ftype == T.SQUARE or f.ftype == T.MARCH:
		return
	var men := mini(ceili(float(f.layout_strength()) / f.companies), f.strength - 100)
	if men < 20:
		return
	var s := Formation.new()
	s.id = formations.size()
	s.army = f.army
	s.brigade = f.brigade
	f.add(s)
	s.is_skirmisher = true
	s.title = ("Voltigeurs, " if f.army == 0 else "Light company, ") + f.title
	s.label = ("volt. " if f.army == 0 else "lt coy ") + f.label
	s.commander = names.commander(f.army, Command.Level.BATTALION)
	s.ranks = 2
	s.companies = 2
	s.max_strength = men
	s.strength = men
	s.morale = f.morale
	s.morale_cap = f.morale_cap
	s.facing = f.facing
	s.prev_facing = f.facing
	# From the place of the light company, on the left of the line.
	var company_w: float = (f.fp.x - Formation.GUARD_W) / f.companies if f.ftype == T.LINE else 0.0
	s.pos = f.pos + f.right() * (-0.5 * f.fp.x + 0.5 * company_w)
	s.prev_pos = s.pos
	s.ftype_from = T.LINE
	s.ftype = T.OPEN
	s.trans_start = time
	s.trans_dur = Formation.OPEN_FORM_T
	s.fire_auto = false
	s.fire_mode = F.AT_WILL
	s.activity = Formation.Activity.SKIRMISHING
	BattalionBrain.set_screen_width(s, f)
	s.refresh_shape()
	s.cpos = s.center()
	BattalionBrain.march_to(self, s, f.pos + f.forward() * BattalionBrain.SCREEN_DEPTH, f.facing, T.OPEN, T.OPEN)
	f.strength -= men
	f.held_out = men
	f.absent_mask |= 1
	f.skirmishers = s
	f.refresh_shape()
	f.render_dirty = true
	formations.append(s)
	events.append({"type": "formation_spawned", "f": s})
	events.append({"type": "skirmishers", "f": f, "out": true})


## The skirmishers are back: their survivors take their places in the ranks.
func absorb_skirmishers(f: Formation) -> void:
	var s: Formation = f.skirmishers
	f.strength += s.strength
	_skirmishers_gone(f)
	s.absorbed = true
	s.dead = true
	s.render_dirty = true
	f.subordinates.erase(s)
	events.append({"type": "skirmishers", "f": f, "out": false})


## The battalion closes its ranks over the company's places (back, or lost).
func _skirmishers_gone(f: Formation) -> void:
	f.held_out = 0
	f.absent_mask &= ~1
	f.skirmishers = null
	f.skirmish_next = time + 120.0
	f.refresh_shape()
	f.render_dirty = true


# ---------------------------------------------------------------- charges

## A bayonet charge: approach at the pas de charge; at 50 m the defender either
## breaks or stands and gives a closing volley; the attacker then either recoils
## or goes in, and a short melee decides it. Most charges were decided before
## the bayonets crossed, and so are these.
class Charge:
	enum Phase { APPROACH, VOLLEY, MELEE }
	var attacker
	var defender
	var phase: int = Phase.APPROACH
	var t := 0.0      # phase began
	var until := 0.0  # phase ends
	var start_a := 0  # strengths when the melee began
	var start_d := 0


const CHARGE_TEST_GAP := 50.0
## Fire shakes a battalion charging home this much less than one standing.
const CHARGE_ELAN := 0.5
## Share of the defender's muskets loaded for a closing volley, by its fire:
## a battalion firing by volleys is loaded between them; firing by platoons,
## some companies always are (the point of it); firing at will, only some men.
const CLOSING_VOLLEY := [1.0, 0.5, 0.3, 1.0]
## How steady each formation is against a charge (line, column, square, march).
const CHARGE_STEADINESS := [0.05, 0.1, 0.35, -0.3]
var charges: Array = []


func start_charge(a: Formation, d: Formation) -> void:
	var c := Charge.new()
	c.attacker = a
	c.defender = d
	c.t = time
	a.charge = c
	a.activity = Formation.Activity.CHARGING
	a.target_enemy = d
	a.halted = false
	a.retiring = false
	a.march_ftype = a.ftype
	a.target_ftype = a.ftype
	charges.append(c)
	events.append({"type": "charge", "f": a, "target": d})


func _step_charges() -> void:
	if charges.is_empty():
		return
	for c: Charge in charges.duplicate():
		var a: Formation = c.attacker
		var d: Formation = c.defender
		if a.dead or a.routing:
			_end_charge(c)
			continue
		if d.dead or d.routing:
			_charge_won(c)
			continue
		var to: Vector2 = d.cpos - a.pos
		var gap := to.length() - d.fp.y * 0.5
		match c.phase:
			Charge.Phase.APPROACH:
				a.target_pos = d.cpos - to.normalized() * (d.fp.y * 0.5 + 2.0)
				a.target_facing = Orientation.yaw_of(to)
				a.has_target = true
				if gap <= CHARGE_TEST_GAP:
					_defender_test(c)
				elif time - c.t > 240.0:
					_end_charge(c)  # never got there
			Charge.Phase.VOLLEY:
				if time >= c.until:
					_attacker_test(c)
			Charge.Phase.MELEE:
				a.has_target = false
				if tick_count % 10 == 0:
					# Bayonet and butt: losses on both sides, every second.
					_melee_losses(a, d)
					_melee_losses(d, a)
				if time >= c.until:
					_melee_decides(c)


## The defender sees the charge come on. Does he stand?
func _defender_test(c: Charge) -> void:
	var a: Formation = c.attacker
	var d: Formation = c.defender
	var steady: float = d.morale + CHARGE_STEADINESS[d.ftype] + rng.randf_range(-0.25, 0.25)
	var loaded: float = CLOSING_VOLLEY[d.fire_now] if d.firing or d.fire_now != F.VOLLEY else (1.0 if time - d.last_shot > 12.0 else 0.0)
	steady += 0.1 * loaded
	var from: Vector2 = (a.cpos - d.cpos).normalized()
	if d.ftype != T.SQUARE and absf(d.forward().angle_to(from)) > deg_to_rad(65.0):
		steady -= 0.3  # taken in flank
	var shock: float = 0.45 + 0.25 * a.morale + (0.08 if a.ftype == T.COLUMN else 0.0)
	shock += clampf((float(a.strength) / maxf(d.strength, 1.0) - 1.0) * 0.15, -0.1, 0.15)
	if steady < shock:
		d.threat_dir = from
		_start_rout(d)
		events.append({"type": "charge_result", "f": a, "target": d, "result": "broke"})
		return
	c.phase = Charge.Phase.VOLLEY
	c.t = time
	c.until = time + 1.5
	if loaded > 0.0 and d.ftype != T.MARCH:
		# The closing volley, at thirty paces.
		var cas := int(round(d.firing_muskets() * loaded * 1.5 * hit_chance(d, a, CHARGE_TEST_GAP * 0.5) * rng.randf_range(0.6, 1.4)))
		d.last_volley = time + 0.3
		d.last_shot = d.last_volley
		d.next_fire = time + 20.0
		d.render_dirty = true
		events.append({"type": "volley", "f": d, "t": d.last_volley})
		_hits.append([d.last_volley + 0.2, a, cas, 1.0, 1.0])


## Through the smoke: does the attacker go on?
func _attacker_test(c: Charge) -> void:
	var a: Formation = c.attacker
	var d: Formation = c.defender
	var push: float = a.morale + rng.randf_range(-0.25, 0.25) + (0.15 if a.charge_below > 1.0 else 0.0) + 0.1 * a.aggression
	if push < 0.55:
		# Recoils: falls back in disorder, shaken.
		_end_charge(c)
		a.morale -= 0.1
		a.set_morale_state(Formation.Morale.SHAKEN, time)
		a.threat_dir = (d.cpos - a.cpos).normalized()
		a.target_pos = a.pos - a.threat_dir * BattalionBrain.FALLBACK_DISTANCE
		a.target_facing = a.facing
		a.has_target = true
		a.retiring = true
		events.append({"type": "charge_result", "f": a, "target": d, "result": "recoiled"})
		return
	c.phase = Charge.Phase.MELEE
	c.t = time
	c.until = time + rng.randf_range(10.0, 30.0)
	c.start_a = a.strength
	c.start_d = d.strength


func _melee_losses(f: Formation, by: Formation) -> void:
	var cas := mini(int(round(by.strength * 0.006 * rng.randf_range(0.5, 1.5))), f.strength)
	if cas > 0:
		f.strength -= cas
		f.refresh_shape()
		f.render_dirty = true
		f.morale -= float(cas) / f.max_strength * 3.0
		events.append({"type": "casualties", "f": f, "n": cas})


## The side whose spirit has held up better against its losses stays.
func _melee_decides(c: Charge) -> void:
	var a: Formation = c.attacker
	var d: Formation = c.defender
	var sa: float = a.morale * a.strength / maxf(c.start_a, 1.0) + rng.randf_range(-0.1, 0.1)
	var sd: float = d.morale * d.strength / maxf(c.start_d, 1.0) + CHARGE_STEADINESS[d.ftype] * 0.5 + rng.randf_range(-0.1, 0.1)
	if sa > sd:
		d.threat_dir = (a.cpos - d.cpos).normalized()
		_start_rout(d)
		events.append({"type": "charge_result", "f": a, "target": d, "result": "won"})
		_charge_won(c)
	else:
		a.threat_dir = (d.cpos - a.cpos).normalized()
		events.append({"type": "charge_result", "f": a, "target": d, "result": "repulsed"})
		_start_rout(a)


## The defender has gone: carry on 30 m into his ground and halt there,
## disordered by the rush.
func _charge_won(c: Charge) -> void:
	var a: Formation = c.attacker
	_end_charge(c)
	a.target_pos = a.pos + a.forward() * 30.0
	a.target_facing = a.facing
	a.has_target = true
	a.next_fire = time + 20.0


func _end_charge(c: Charge) -> void:
	charges.erase(c)
	var a: Formation = c.attacker
	if a.charge == c:
		a.charge = null
		a.activity = Formation.Activity.IDLE
		a.has_target = false

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
