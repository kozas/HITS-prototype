extends "res://src/command.gd"
## One battalion: the atom of the simulation, and the bottom of the chain of
## command (it can take orders like any other Command).
## Individual soldiers have no CPU state at all; soldier.gdshader derives every
## man, officer and drummer from these fields. footprint_for() and colour_pos()
## must mirror the shader's battalion geometry (bn_make / bn_size / staff_pos).

## OPEN: skirmish order, men in pairs a few paces apart with a support group
## behind. Only a light company detached from its battalion takes it.
enum Type { LINE, COLUMN, SQUARE, MARCH, OPEN }
const TYPE_NAMES := ["Line", "Column", "Square", "March", "Open order"]

const FILE_W := 0.6
const RANK_D := 0.65
const SERRE := 1.3
const GUARD_W := 1.2
const ORDINARY_STEP := 0.82  # pas ordinaire: 76 paces/min of 0.65 m
const QUICK_STEP := 1.08     # pas accéléré: 100 paces/min
const CHARGE_STEP := 1.45    # pas de charge: 120 paces/min, breaking into a run
const ROUT_SCATTER_T := 8.0  # seconds for a routing battalion to scatter fully
const RALLY_REFORM_T := 15.0 # seconds for a rallying battalion to re-form
## Fire cycles (s): a company's turn comes round, or a man reloads, this often.
const PLATOON_CYCLE := 20.0
const AT_WILL_CYCLE := 16.0
## Open order (mirrors soldier.gdshader): pairs this far apart, and a quarter of
## the company kept back as a support this far behind the chain.
const SKIRMISH_GAP := 4.0
const SUPPORT_DIST := 40.0
const OPEN_FORM_T := 12.0  # seconds for a company to run out into open order

var id := 0         # index in BattleSim.formations
var brigade := 0    # index in BattleSim.brigades (also `parent`)
# label: short, e.g. "1/45e"; title: e.g. "1er bataillon, 45e de Ligne"
var strength := 600
var max_strength := 600
var ranks := 3
var companies := 6

# Anchor = centre of the front rank. Facing is a Godot yaw (forward = -Z rotated).
var pos := Vector2.ZERO
var facing := 0.0
var prev_pos := Vector2.ZERO
var prev_facing := 0.0

var ftype: int = Type.COLUMN
var ftype_from: int = Type.COLUMN
var trans_start := -1000.0
var trans_dur := 0.0

var has_target := false
var target_pos := Vector2.ZERO
var target_facing := 0.0
var target_ftype: int = Type.LINE
var march_ftype: int = Type.COLUMN
## Its place in the brigade, as last laid out by the brigadier.
var station := Vector2.ZERO
var station_facing := 0.0
var station_ftype: int = Type.LINE
var moving := false
var moving_since := -1000.0  # guides step out ahead when the battalion advances
var slope_factor := 1.0

## Dressing: the brigadier slows a battalion that gets ahead of the line and
## hurries one that lags (0..1.3).
var pace_mul := 1.0
## Stepping back facing the enemy (falling back in order), not turning to march.
var retiring := false

# --- morale: how steady the men are, apart from what they are doing
enum Morale { STEADY, SHAKEN, ROUTING, RALLYING, BROKEN }
const MORALE_NAMES := ["steady", "shaken", "routing", "rallying", "broken"]
var morale := 1.0
## Ceiling on morale: a battalion that has run once is never quite as steady.
var morale_cap := 1.0
var morale_state: int = Morale.STEADY
## Mirrors of morale_state (set_morale_state keeps them), read in hot loops.
var routing := false
var broken := false
var broken_at := 0.0
## Rout scatter clock for the shader: 0 steady, t + 1 routing since t,
## -(t + 1) rallying since t; see soldier.gdshader.
var rout_t := 0.0
var rally_point := Vector2.ZERO
var routed_at := -1000.0
var dead := false

# --- activity: what the battalion is doing
enum Activity { IDLE, MANOEUVRE, FIRING, CHARGING, SKIRMISHING }
const ACTIVITY_NAMES := ["idle", "manoeuvring", "firing", "charging", "skirmishing"]
var activity: int = Activity.IDLE
var engaged := false
var threat_dir := Vector2.ZERO
var target_enemy = null  # the enemy battalion it is firing on, or charging

# --- fire. VOLLEY: the whole battalion at the word; PLATOON: company after
# company, rolling from the right; AT_WILL: every man as he loads; HOLD: none.
enum Fire { VOLLEY, PLATOON, AT_WILL, HOLD }
const FIRE_NAMES := ["Volley", "By platoon", "At will", "Hold fire"]
var fire_mode: int = Fire.VOLLEY  # as ordered, when not fire_auto
var fire_auto := true  # the chef de bataillon chooses (doctrine)
var fire_now: int = Fire.VOLLEY  # the fire actually in use (drawn by the shader)
var last_shot := -1000.0  # any fire; a battalion that has fired lately is not loaded
var last_volley := -1000.0
var next_fire := 0.0
## Continuous fire (platoon, at will): when it began and ended. The shader works
## out every company's or man's shots from these, as the sim does.
var fire_start := -1000.0
var fire_end := -1000.0
var firing := false
## Fire at will is hard to stop: orders wait until the men are got in hand.
var obey_at := 0.0
var cas_accum := 0.0  # fractional casualties owed to the target (deterministic)

# --- standing orders, from the order being carried out (intensity)
## Halts to fire when an enemy to the front is this close (0: never halts).
var halt_range := 180.0
## Charges an enemy whose morale is below this (0: never; > 1: always).
var charge_below := 0.0
## Falls back in order when its own morale drops below this.
var fallback_below := 0.3
## Launches its charge when the fronts are this far apart.
var charge_gap := 0.0
## Stands: does not move from its place to close with the enemy.
var stand := false
## Halted to give fire rather than press on (set by the brain, obeyed by _move).
var halted := false
var charge = null  # BattleSim.Charge in progress, as the attacker
var absent_mask := 0  # see company_absent()
## Men of the absent company: the battalion keeps their places in its ranks
## (layout strength = strength + held_out) so the rest do not shift about.
var held_out := 0
var skirmishers = null  # its light company out as a skirmish screen (a Formation)
## This is a light company out skirmishing (`parent` is its battalion).
var is_skirmisher := false
var recalled := false   # skirmishers called in: running back to rejoin
## Throws out its skirmishers by itself when the enemy is near (doctrine).
var skirmish_auto := false
var skirmish_next := 0.0  # not again before this (just called in)
var absorbed := false   # skirmishers back in their battalion (dead = gone, not killed)

var cpos := Vector2.ZERO  # cached center(), refreshed every sim tick

# What the player knows about this formation (enemy side): drives the map.
var los_visible := true
var seen_time := -1.0e9
var seen_pos := Vector2.ZERO
var seen_facing := 0.0
var seen_ftype := 0

var render_dirty := true
var fp := Vector2.ONE  # cached footprint; refresh_shape() when type or strength change
var fp_radius := 1.0   # half the footprint's diagonal (cached with fp)
var axis_r := Vector2.RIGHT  # right() as of the last grid rebuild (2 Hz)


func _init() -> void:
	level = Level.BATTALION


func battalions_all() -> Array:
	return [self]


func position() -> Vector2:
	return cpos


func is_gone() -> bool:
	return dead


func refresh_shape() -> void:
	fp = footprint_as(ftype)
	fp_radius = fp.length() * 0.5


## Men the shader lays out: those present plus the places kept for those away.
func layout_strength() -> int:
	return strength + held_out


func footprint_as(type: int) -> Vector2:
	return footprint_for(type, layout_strength(), ranks, companies)


func forward() -> Vector2:
	return Vector2(-sin(facing), -cos(facing))


func right() -> Vector2:
	return Vector2(cos(facing), -sin(facing))


func back() -> Vector2:
	return Vector2(sin(facing), cos(facing))


func footprint() -> Vector2:
	return fp


## Centre of the formation's footprint (the anchor is the front-rank centre).
func center() -> Vector2:
	return pos + Vector2(sin(facing), cos(facing)) * (fp.y * 0.5)


func is_transitioning(t: float) -> bool:
	return t < trans_start + trans_dur


func begin_transition(new_type: int, t: float) -> void:
	if new_type == ftype:
		return
	ftype_from = ftype
	ftype = new_type
	refresh_shape()
	trans_start = t
	trans_dur = transition_time(ftype_from, ftype)
	render_dirty = true


func set_morale_state(s: int, t: float) -> void:
	if s == morale_state:
		return
	var was_routing := routing
	morale_state = s
	routing = s == Morale.ROUTING or s == Morale.BROKEN
	broken = s == Morale.BROKEN
	if routing and not was_routing:
		rout_t = t + 1.0
		render_dirty = true
	elif s == Morale.RALLYING:
		rout_t = -(t + 1.0)
		render_dirty = true


## Shader rout scatter 0..1 at time t (mirrors soldier.gdshader).
func rout_amount(t: float) -> float:
	if rout_t > 0.0:
		return clampf((t - (rout_t - 1.0)) / ROUT_SCATTER_T, 0.0, 1.0)
	if rout_t < 0.0:
		return clampf(1.0 - (t - (-rout_t - 1.0)) / RALLY_REFORM_T, 0.0, 1.0)
	return 0.0


## Companies detached from the battalion (bit k: company k is away skirmishing).
func company_absent(k: int) -> bool:
	return (absent_mask >> k) & 1 == 1


func is_steady() -> bool:
	return morale_state == Morale.STEADY or morale_state == Morale.SHAKEN


## Lines advance at the ordinary step; columns manoeuvre at the quick step;
## the charge goes in at the pas de charge.
func speed() -> float:
	if routing:
		return 2.4
	if activity == Activity.CHARGING:
		return CHARGE_STEP
	if retiring:
		return ORDINARY_STEP * 0.8
	match ftype:
		Type.LINE:
			return ORDINARY_STEP
		Type.COLUMN, Type.MARCH, Type.OPEN:
			return QUICK_STEP
		_:
			return 0.15


## A wheel can go no faster than the outer flank can march at the quick step:
## about 1 degree a second for a battalion in line. Skirmishers just turn.
func turn_rate() -> float:
	if ftype == Type.OPEN:
		return deg_to_rad(15.0)
	return minf(QUICK_STEP / maxf(fp.x * 0.5, 1.0), deg_to_rad(15.0))


## Muskets that can bear on a target to the front (front two ranks; less any
## company away skirmishing). Skirmishers: every man in the chain.
func firing_muskets() -> int:
	var present := 1.0 - float(held_out) / maxf(layout_strength(), 1.0)
	match ftype:
		Type.LINE, Type.COLUMN:
			return mini(strength, int(fp.x / FILE_W * 2.0 * present))
		Type.SQUARE:
			return strength / 8
		Type.OPEN:
			return strength - strength / 4
		_:
			return 0


## How long a change of formation takes: the farthest section marches from its
## old place to its new one at the quick step (as the shader animates it).
func transition_time(a: int, b: int) -> float:
	if a == Type.OPEN or b == Type.OPEN:
		return OPEN_FORM_T
	var fa := footprint_as(a)
	var fb := footprint_as(b)
	return 3.0 + Vector2(absf(fa.x - fb.x) * 0.5, maxf(fa.y, fb.y)).length() / QUICK_STEP


## (width, depth) in metres; the anchor is the centre of the front rank.
## Mirrors bn_make / bn_size in soldier.gdshader.
static func footprint_for(type: int, n: int, rk: int, c: int) -> Vector2:
	var g := _geom(n, rk, c)
	match type:
		Type.LINE:
			return Vector2(c * g.x + GUARD_W, g.y)
		Type.COLUMN:
			return Vector2(2.0 * g.x + GUARD_W, (c / 2 - 1) * maxf(0.5 * g.x, g.y + 2.0) + g.y)
		Type.SQUARE:
			return Vector2(2.0 * g.x, 2.0 * rk * RANK_D + maxi(c / 2 - 2, 0) * g.x)
		Type.OPEN:
			var support := n / 4
			var pairs := (n - support + 1) / 2
			return Vector2(maxf(pairs * SKIRMISH_GAP, 4.0), SUPPORT_DIST + 2.0 * RANK_D)
		_:
			return Vector2(g.z, (2 * c - 1) * maxf(g.z, g.y + 3.0) + g.y)


## Where the colours stand (local x, z), in the middle of the colour guard.
func colour_pos(type: int) -> Vector2:
	var g := _geom(layout_strength(), ranks, companies)
	match type:
		Type.SQUARE:
			return Vector2(0, footprint_as(type).y * 0.5 - 1.0 + RANK_D)
		Type.MARCH:
			return Vector2(0, 2.0 * maxf(g.z, g.y + 3.0) - 2.5 + RANK_D)
		_:
			return Vector2(0, RANK_D)


## (company frontage incl. the captain's file, company depth, 1st section frontage)
static func _geom(n: int, rk: int, c: int) -> Vector3:
	var pc := maxi((maxi(n, 1) + c - 1) / c, 1)
	var nf := maxi((pc + rk - 1) / rk, 1)
	return Vector3((nf + 1) * FILE_W, rk * RANK_D + SERRE, (nf - nf / 2) * FILE_W)
