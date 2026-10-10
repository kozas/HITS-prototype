extends RefCounted
## A drill ground for headless tests: a sim with a handful of single-battalion
## brigades placed by hand, and helpers to give them orders without couriers.

const Terrain = preload("res://src/terrain.gd")
const BattleSim = preload("res://src/battle_sim.gd")
const Formation = preload("res://src/formation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")

## Open, gently rolling ground on the "hill" map, well away from the hill.
const ORIGIN := Vector2(-1200.0, 300.0)

static var _terrain = null


static func terrain():
	if _terrain == null:
		_terrain = Terrain.new()
		_terrain.generate(Terrain.MAPS.hill)
	return _terrain


static func free_terrain() -> void:
	if _terrain != null:
		_terrain.free()
		_terrain = null


static func new_sim(rng_seed := 1815):
	var sim = BattleSim.new(terrain())
	sim.rng.seed = rng_seed
	sim.ai_enabled = [false, false]
	return sim


## One battalion (in a brigade of its own) at ORIGIN + `at`, facing `yaw`.
static func battalion(sim, army: int, at: Vector2, yaw: float, ftype: int, men := 600):
	var b = sim._add_brigade(army, 0)
	var f = sim._add_battalion(b, men, ORIGIN + at, yaw, ftype)
	return f


## A brigade of `n` battalions drawn up abreast in `ftype`, the centre of its
## front at ORIGIN + `at`.
static func brigade(sim, army: int, at: Vector2, yaw: float, ftype: int, n := 4):
	var b = sim._add_brigade(army, 0)
	for k in n:
		sim._add_battalion(b, 600, ORIGIN + at, yaw, ftype)
	var slots: Array = sim._brigade_slots(b.battalions, ORIGIN + at, yaw, ftype)
	for k in n:
		b.battalions[k].pos = slots[k]
		b.battalions[k].prev_pos = slots[k]
	return b


## Call once every unit is placed.
static func ready(sim) -> void:
	for army in 2:
		sim._organise(army)
	sim._rebuild_grid()
	for f in sim.formations:
		f.cpos = f.center()


## An order handed straight to `u` (no courier, no staff delay), from its own
## commander unless `issuer` says otherwise.
static func order(sim, u, kind: int, objective, issuer = null):
	var o = sim.new_order(u, kind, objective, issuer if issuer != null else u.parent)
	sim._hand_over(o, sim.time)
	return o


static func run(sim, seconds: float, until: Callable = Callable()) -> void:
	var end: float = sim.time + seconds
	while sim.time < end:
		sim._tick()
		sim.events.clear()
		if until.is_valid() and until.call():
			return


## Runs, keeping the events, and returns them.
static func run_events(sim, seconds: float) -> Array:
	var out := []
	var end: float = sim.time + seconds
	while sim.time < end:
		sim._tick()
		out.append_array(sim.events)
		sim.events.clear()
	return out


static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)
