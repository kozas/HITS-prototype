extends RefCounted
## The chef de bataillon. Two jobs:
## - execute(): turn an order addressed to this battalion (MOVE / ATTACK / HOLD
##   / REJOIN) into drill: where to go, in what formation, how hard to press.
## - think(): once a second, the standing orders every battalion follows whoever
##   commands it: pick a target, give fire in the chosen manner, halt or press on
##   as the intensity says, fall back when shaken, charge when the moment comes,
##   run when broken and rally when out of danger.
## The drill itself (marching, wheeling, forming) is BattleSim._move at 10 Hz.

const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Orientation = preload("res://src/orientation.gd")
const Doctrine = preload("res://src/ai/doctrine.gd")
const Objective = preload("res://src/objective.gd")
const T := Formation.Type
const F := Formation.Fire
const M := Formation.Morale
const A := Formation.Activity

const FIRE_RANGE := 180.0
const SEEK_RANGE := 360.0
## Least morale a battalion needs to launch a charge.
const CHARGE_MORALE := 0.35
## A routed battalion that is out of danger rallies at its rally point, or
## after this long on the run.
const RALLY_AFTER := 90.0
## Routing battalions run this far back from the danger to re-form.
const RALLY_DISTANCE := 350.0
## How a unit marches when left to choose (choose_march):
## farther than this, and in contact, it goes in column of attack;
const COLUMN_DISTANCE := 300.0
## a line in contact advances or retires in line up to this far,
const LINE_ADVANCE := 400.0
## and shifts sideways by the flank up to this far;
const FLANK_MARCH := 150.0
## a long march with no formed enemy within ROUTE_CLEAR of either end goes in
## route column.
const ROUTE_DISTANCE := 800.0
const ROUTE_CLEAR := 1500.0
## In place when this close.
const ARRIVED := 25.0
const FALLBACK_DISTANCE := 100.0
## Skirmishers work this far ahead of their battalion, and run back to it when
## formed enemy comes within SCREEN_CLEAR of them.
const SCREEN_DEPTH := 150.0
const SCREEN_CLEAR := 120.0
## ...or when their own battalion comes up to within this distance of them.
const SCREEN_MIN := 60.0
## A battalion left to itself throws out its skirmishers when formed enemy is
## between these distances.
const SKIRMISH_FROM := Vector2(300.0, 800.0)

## Standing orders by intensity (Order.Intensity):
##   [halt to fire at (m, 0 = never), charge when enemy morale below,
##    fall back when own morale below, launch the charge at this gap between fronts (m)]
const STANDING := [
	[150.0, 0.0, 0.6, 0.0],    # PROBE: feel for the enemy, keep your distance, never close
	[70.0, 0.5, 0.4, 80.0],    # PRESS: close to musket range, charge a wavering enemy
	[0.0, 2.0, 0.25, 150.0],   # ALL_OUT: straight in, the pas de charge over the last 150 m
]
## Marching, or holding: halt and return fire when engaged; no charging.
const STANDING_MOVE := [FIRE_RANGE, 0.0, 0.3, 0.0]

## Per fire mode (Formation.Fire): hit chance relative to a volley, and the
## shock to the target's morale per casualty (a volley's crash is the worst).
const ACCURACY := [1.0, 1.0, 0.75, 0.0]
const SHOCK := [1.0, 0.65, 0.5, 0.0]


# ---------------------------------------------------------------- orders

## Acts on `o`. False if the battalion cannot take it at all.
static func execute(sim, f, o) -> bool:
	if f.dead:
		return false
	if o.kind == Order.Kind.REJOIN:
		o.detached = false
		f.stand = false
		apply_standing(f, Order.Kind.MOVE, o.intensity)
		return true
	apply_standing(f, o.kind, o.intensity)
	apply_preferences(sim, f, o)
	if not f.routing:
		_pursue(sim, f, o, true)
	return true


## Standing orders that come with an order of this kind and intensity. Brigades
## pass theirs down the same way.
static func apply_standing(f, kind: int, intensity: int) -> void:
	var s: Array = STANDING_MOVE
	if kind == Order.Kind.ATTACK:
		s = STANDING[intensity]
	f.halt_range = s[0]
	f.charge_below = s[1]
	f.fallback_below = s[2]
	f.charge_gap = s[3]
	f.stand = kind == Order.Kind.HOLD


static func apply_preferences(sim, f, o) -> void:
	f.fire_auto = o.fire_mode < 0
	if not f.fire_auto:
		f.fire_mode = o.fire_mode
	var doctrine := Doctrine.of(f.army)
	f.skirmish_auto = o.skirmishers < 0 and ((o.kind == Order.Kind.ATTACK and doctrine.skirmish_in_attack)
		or (o.kind == Order.Kind.HOLD and doctrine.skirmish_in_defence))
	if o.skirmishers >= 0:
		sim.set_skirmishers(f, o.skirmishers == 1)


## Head for the order's objective (again, if pushed off it or the target moved).
static func _pursue(sim, f, o, first: bool) -> void:
	var doctrine := Doctrine.of(f.army)
	var dest: Vector2 = o.dest()
	if o.kind == Order.Kind.ATTACK and o.objective.kind == Objective.Kind.UNIT:
		# Close on the enemy battalion; the standing orders halt or charge.
		var to: Vector2 = dest - f.cpos
		if to.length() > 1.0:
			dest -= to.normalized() * 20.0
	elif o.kind == Order.Kind.HOLD and f.cpos.distance_to(dest) < ARRIVED * 2.0 and first:
		dest = f.pos  # hold where it stands: just face the right way
	var ft: int = o.ftype
	if ft < 0:
		ft = doctrine.attack_ftype if o.kind == Order.Kind.ATTACK else (f.ftype if f.ftype != T.MARCH else T.LINE)
		if first:
			o.ftype = ft
	var facing: float
	if o.kind == Order.Kind.ATTACK:
		var to: Vector2 = o.dest() - f.pos
		facing = Orientation.yaw_of(to) if to.length() > 1.0 else f.facing
		o.facing = facing
		o.facing_reason = Orientation.Reason.ENEMY
	elif o.facing == null or not first:
		var d := Orientation.decide(sim, f, dest, ft)
		facing = d.facing
		o.facing = facing
		o.facing_reason = d.reason
	else:
		facing = o.facing
	march_to(sim, f, dest, facing, ft, o.march_ftype)


## Drill: march to `dest`, front `facing` there in formation `ft`, marching in
## formation `march` (AUTO: the chef de bataillon chooses, see choose_march).
static func march_to(sim, f, dest: Vector2, facing: float, ft: int, march := Order.AUTO) -> void:
	if f.firing and f.fire_now == F.AT_WILL and sim.time >= f.obey_at:
		# Men firing at will take time to be got in hand.
		f.obey_at = sim.time + sim.rng.randf_range(10.0, 20.0)
	f.target_pos = dest
	f.target_facing = facing
	f.target_ftype = ft
	f.has_target = true
	f.retiring = false
	f.march_ftype = march if march >= 0 else choose_march(sim, [f], f.pos, dest, ft)


## How a unit (one battalion, or a brigade deciding for all its battalions)
## should march from `from` to `dest`, to form `ft` there:
## - route column for a long march with no formed enemy near either end;
## - in line, for a line in contact going a short way straight ahead or back
##   (or a shorter way sideways, by the flank): it keeps its front throughout;
## - as it stands, for a column, or for a short move;
## - otherwise column of attack, deploying at the end.
## A march column or skirmishers march as they are.
static func choose_march(sim, units: Array, from: Vector2, dest: Vector2, ft: int, pref := Order.AUTO) -> int:
	if pref >= 0:
		return pref
	if ft == T.MARCH or ft == T.OPEN:
		return ft
	var d := from.distance_to(dest)
	var army: int = units[0].army
	if d > ROUTE_DISTANCE and sim.nearest_enemy(from, army, ROUTE_CLEAR, true) == null \
			and sim.nearest_enemy(dest, army, ROUTE_CLEAR, true) == null:
		return T.MARCH
	if d <= ARRIVED * 2.0:
		return ft
	var all_line := true
	var all_column := true
	var front := Vector2.ZERO
	for f in units:
		all_line = all_line and f.ftype == T.LINE
		all_column = all_column and (f.ftype == T.COLUMN or f.ftype == T.MARCH)
		front += f.forward()
	if all_line and ft == T.LINE:
		var along := absf((dest - from).normalized().dot(front.normalized()))
		return T.LINE if d <= (LINE_ADVANCE if along >= cos(PI * 0.25) else FLANK_MARCH) else T.COLUMN
	if all_column:
		return T.COLUMN  # move as it is and deploy on arrival
	return ft if d <= COLUMN_DISTANCE else T.COLUMN


static func halt(f) -> void:
	f.has_target = false
	f.retiring = false


# ---------------------------------------------------------------- standing orders

## Once a second (staggered with the other 1 Hz work).
static func think(sim, f, dt: float) -> void:
	if f.is_skirmisher:
		_skirmish(sim, f, dt)
		return
	f.engaged = false
	f.halted = false
	if f.skirmishers != null and f.skirmishers.dead and not f.skirmishers.absorbed:
		sim._skirmishers_gone(f)  # the company was cut up or ran: close the ranks
	# Formed troops reckon with formed enemy; skirmishers are only a nuisance.
	sim.scan_enemies(f.cpos, f.army, SEEK_RANGE)
	var e = sim.scan_formed
	var sk = sim.scan_any
	var d := INF
	if e != null:
		d = f.cpos.distance_to(e.cpos)
	if f.routing:
		_while_routing(sim, f, e, d, dt)
		return
	if f.morale_state == M.RALLYING:
		if sim.time >= -f.rout_t - 1.0 + Formation.RALLY_REFORM_T:
			f.set_morale_state(M.SHAKEN if f.morale < 0.5 else M.STEADY, sim.time)
			f.activity = A.IDLE
		return
	if e == null or d > FIRE_RANGE:
		f.morale = minf(f.morale_cap, f.morale + (0.004 if e == null else 0.002) * dt)
	if f.morale_state == M.SHAKEN and f.morale > 0.6:
		f.set_morale_state(M.STEADY, sim.time)
	elif f.morale_state == M.STEADY and f.morale < 0.45:
		f.set_morale_state(M.SHAKEN, sim.time)
	if f.charge != null:
		return  # the charge runs itself (BattleSim._step_charges)

	var o = f.order
	var own_order: bool = o != null and o.status == Order.Status.EXECUTING
	if f.skirmish_auto and f.skirmishers == null and sim.time >= f.skirmish_next and f.is_steady() \
			and (f.ftype == T.LINE or f.ftype == T.COLUMN):
		var far = sim.nearest_enemy(f.cpos, f.army, SKIRMISH_FROM.y, true)
		if far != null and far.cpos.distance_to(f.cpos) > SKIRMISH_FROM.x:
			sim.set_skirmishers(f, true)
	if e == null or d > FIRE_RANGE:
		f.activity = A.MANOEUVRE if f.has_target else A.IDLE
		# Nothing formed in range: shoot at skirmishers if standing anyway.
		if sk != null and sk.ftype == T.OPEN and sk.cpos.distance_to(f.cpos) < FIRE_RANGE * 0.8 and not f.moving \
				and absf(f.forward().angle_to(sk.cpos - f.cpos)) < deg_to_rad(65.0) \
				and not f.is_transitioning(sim.time):
			_give_fire(sim, f, sk, f.cpos.distance_to(sk.cpos))
			f.activity = A.FIRING
		else:
			cease_fire(sim, f)
		if own_order:
			_follow_order(sim, f, o)
		return

	f.engaged = true
	f.threat_dir = (e.cpos - f.cpos) / maxf(d, 0.1)
	f.target_enemy = e
	var trans: bool = f.is_transitioning(sim.time)
	if f.ftype == T.MARCH and not trans:
		# Caught in route column: form line to face it.
		f.begin_transition(T.LINE, sim.time)
		cease_fire(sim, f)
		return

	# Shaken under fire: give ground in order, still facing the enemy.
	if f.morale < f.fallback_below and not f.stand and not f.retiring and not trans:
		cease_fire(sim, f)
		f.target_pos = f.pos - f.threat_dir * FALLBACK_DISTANCE
		f.target_facing = f.facing
		f.target_ftype = f.ftype
		f.march_ftype = f.ftype
		f.has_target = true
		f.retiring = true
		f.activity = A.MANOEUVRE
		if f.morale_state == M.STEADY:
			f.set_morale_state(M.SHAKEN, sim.time)
		return

	# The moment for the bayonet: the enemy wavers (or the order is to go in regardless).
	var gap: float = f.pos.distance_to(e.cpos) - e.fp.y * 0.5
	if not f.stand and not f.retiring and not trans and gap < f.charge_gap and e.morale < f.charge_below \
			and f.morale > CHARGE_MORALE and e.is_steady() and f.ftype != T.SQUARE:
		cease_fire(sim, f)
		sim.start_charge(f, e)
		return

	var to: Vector2 = e.cpos - f.cpos
	var can_bear: bool = f.ftype == T.SQUARE or absf(f.forward().angle_to(to)) < deg_to_rad(65.0)
	if not can_bear and not trans and not f.has_target:
		# Wheel to face the threat where it stands.
		f.target_pos = f.pos
		f.target_facing = Orientation.yaw_of(to)
		f.target_ftype = f.ftype
		f.march_ftype = f.ftype
		f.has_target = true
	# Halt to give fire, or press on through it?
	if f.has_target and not f.retiring and (f.target_pos - f.pos).dot(f.threat_dir) > 0.0:
		f.halted = f.stand or d <= f.halt_range
	if can_bear and not trans and (not f.moving or f.halted):
		_give_fire(sim, f, e, d)
		f.activity = A.FIRING
	else:
		cease_fire(sim, f)
		f.activity = A.MANOEUVRE


## Carry on with the battalion's own order: re-aim on a moving target, resume
## after a rally or a fall-back, and report it done.
static func _follow_order(sim, f, o) -> void:
	match o.kind:
		Order.Kind.ATTACK:
			if o.objective.kind == Objective.Kind.UNIT:
				var u = o.objective.unit
				if u.is_gone() or u.routing:
					sim.complete_order(f)
					return
				if not f.has_target or f.target_pos.distance_to(o.dest()) > 40.0:
					_pursue(sim, f, o, false)
			elif not f.has_target:
				if f.pos.distance_to(o.dest()) < ARRIVED:
					sim.complete_order(f)
				else:
					_pursue(sim, f, o, false)
		Order.Kind.MOVE:
			if not f.has_target:
				if f.pos.distance_to(o.dest()) < ARRIVED and f.ftype == o.ftype:
					sim.complete_order(f)
				else:
					_pursue(sim, f, o, false)
		Order.Kind.HOLD:
			pass  # holds until told otherwise
		Order.Kind.REJOIN:
			sim.complete_order(f)


static func _while_routing(sim, f, e, d: float, dt: float) -> void:
	if f.broken:
		if sim.time > f.broken_at + 90.0:
			f.dead = true
			f.render_dirty = true
		return
	var safe: bool = e == null or d > 250.0
	var at_rally: bool = f.pos.distance_to(f.rally_point) < 15.0
	if safe and (at_rally or sim.time - f.routed_at > RALLY_AFTER):
		# Officers rally the men; faster under the brigadier's eye.
		f.morale = minf(f.morale_cap, f.morale + 0.02 * dt * (2.0 if _brigadier_near(f) else 1.0))
	if f.morale > 0.5 and safe:
		f.has_target = false
		f.set_morale_state(M.RALLYING, sim.time)
		f.activity = A.IDLE
		f.begin_transition(T.LINE, sim.time)
		sim.events.append({"type": "rally", "f": f})


## A light company out skirmishing. Its post is SCREEN_DEPTH ahead of its
## battalion's front, parallel to it and as wide as it, and it keeps that post
## as the battalion moves: re-aiming every second, at a pace that keeps up. It
## never turns as a body (open order keeps facing the battalion's front) and
## only halts at its post, or where formed enemy will not let it go further. It
## fires at will whenever it is standing: on enemy skirmishers first, then on
## formed troops. It runs back and rejoins when called in, when formed enemy
## comes within SCREEN_CLEAR, when the battalion forms square or march column,
## or when the battalion comes up to within SCREEN_MIN of it.
static func _skirmish(sim, s, dt: float) -> void:
	var f = s.parent
	s.engaged = false
	s.halted = false
	if s.routing:
		_while_routing(sim, s, sim.nearest_enemy(s.cpos, s.army, SEEK_RANGE), INF, dt)
		return
	if s.morale_state == M.RALLYING:
		if sim.time >= -s.rout_t - 1.0 + Formation.RALLY_REFORM_T:
			s.set_morale_state(M.SHAKEN if s.morale < 0.5 else M.STEADY, sim.time)
			s.recalled = true  # rallied: back to the battalion
			s.begin_transition(T.OPEN, sim.time)
		return
	var alone: bool = f == null or f.dead
	sim.scan_enemies(s.cpos, s.army, SEEK_RANGE)
	var formed = sim.scan_formed
	var screen = sim.scan_open
	if not alone:
		if f.routing or f.ftype == T.SQUARE or f.ftype == T.MARCH:
			s.recalled = true
		elif s.screen_out and (s.pos - f.pos).dot(f.forward()) < SCREEN_MIN:
			s.recalled = true  # the battalion has come up on its screen
	if formed != null and s.pos.distance_to(formed.cpos) < SCREEN_CLEAR:
		s.recalled = true  # measured from the chain, not the support behind it
	if s.recalled and not alone:
		cease_fire(sim, s)
		var home: Vector2 = f.pos - f.right() * f.fp.x * 0.4 + f.back() * 2.0
		if s.pos.distance_to(home) < 15.0:
			sim.absorb_skirmishers(f)
			return
		if not s.has_target or s.target_pos.distance_to(home) > 10.0:
			march_to(sim, s, home, f.facing, T.OPEN, T.OPEN)
		return
	if not alone:
		_keep_station(sim, s, f, formed)
	# The skirmish fight first; formed troops if no skirmishers are in range.
	var e = screen if screen != null and s.cpos.distance_to(screen.cpos) <= FIRE_RANGE else formed
	if e == null or s.cpos.distance_to(e.cpos) > FIRE_RANGE:
		cease_fire(sim, s)
		s.morale = minf(s.morale_cap, s.morale + 0.003 * dt)
		return
	var d: float = s.cpos.distance_to(e.cpos)
	s.engaged = true
	s.threat_dir = (e.cpos - s.cpos) / maxf(d, 0.1)
	s.target_enemy = e
	if not s.moving:
		_give_fire(sim, s, e, d)
	else:
		cease_fire(sim, s)


## The screen's post: SCREEN_DEPTH ahead of the battalion's front, as wide as
## it. Formed enemy close to the post holds the screen where it stands.
static func _keep_station(sim, s, f, formed) -> void:
	set_screen_width(s, f)
	var post: Vector2 = f.pos + f.forward() * SCREEN_DEPTH
	if formed != null and formed.cpos.distance_to(post) < SCREEN_CLEAR + 30.0 \
			and (s.pos - f.pos).dot(f.forward()) < SCREEN_DEPTH:
		halt(s)  # pressed: hold here rather than go on into his line
		return
	if s.pos.distance_to(post) < 20.0:
		s.screen_out = true
	# While the battalion marches, keep re-aiming so the screen moves with it.
	var slack := 3.0 if f.moving else 10.0
	if s.pos.distance_to(post) > slack or absf(angle_difference(s.facing, f.facing)) > 0.1:
		if not s.has_target or s.target_pos.distance_to(post) > slack or absf(angle_difference(s.target_facing, f.facing)) > 0.1:
			march_to(sim, s, post, f.facing, T.OPEN, T.OPEN)


## Stretch (or close) the chain to cover the battalion's frontage in line.
static func set_screen_width(s, f) -> void:
	var pairs: int = maxi((s.strength - s.strength / 4 + 1) / 2, 1)
	var gap: float = clampf(f.footprint_as(T.LINE).x / pairs, Formation.SKIRMISH_GAP_RANGE.x, Formation.SKIRMISH_GAP_RANGE.y)
	if absf(gap - s.open_gap) > 0.25:
		s.open_gap = gap
		s.refresh_shape()
		s.render_dirty = true

## The brigadier is with his steady battalions: is that within reach?
static func _brigadier_near(f) -> bool:
	if f.parent == null or f.parent.level != f.parent.Level.BRIGADE:
		return false
	var c := Vector2.ZERO
	var n := 0
	for o in f.parent.battalions:
		if not o.dead and not o.routing:
			c += o.cpos
			n += 1
	return n > 0 and (c / n).distance_to(f.cpos) < 300.0


# ---------------------------------------------------------------- fire

## Fire on `e` in the manner ordered, or chosen by doctrine: an opening volley,
## then the army's usual fire.
static func _give_fire(sim, f, e, d: float) -> void:
	var mode: int = f.fire_mode
	if f.fire_auto:
		var doctrine := Doctrine.of(f.army)
		var fresh: bool = sim.time - f.last_shot > 60.0
		mode = F.VOLLEY if fresh and doctrine.opening_volley else doctrine.fire
	if mode == F.HOLD or (not f.is_skirmisher and sim.masked(f, e, d)):
		cease_fire(sim, f)  # ordered to hold, or its own skirmishers are in the way
		return
	if mode == F.VOLLEY:
		if f.firing:
			cease_fire(sim, f)
		f.fire_now = F.VOLLEY
		if sim.time >= f.next_fire:
			sim.volley(f, e, d)
		return
	if not f.firing or f.fire_now != mode:
		# Muskets come up first; the first company fires (or the first men) after that.
		f.firing = true
		f.fire_now = mode
		f.fire_start = sim.time + 1.6
		f.fire_end = 1.0e9
		f.render_dirty = true
	sim.continuous_fire(f, e, d, sim.time, sim.time + 1.0)


static func cease_fire(sim, f) -> void:
	if f.firing:
		f.firing = false
		f.fire_end = sim.time
		f.render_dirty = true
