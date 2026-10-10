extends RefCounted
## The brigadier: turns the brigade's order into drill for its battalions.
## Today he knows one thing, MOVE: lay the battalions out at the destination in
## the ordered formation, on a front of his own choosing. ATTACK and HOLD, the
## skirmish screen, second line and charges come with the next plan.

const Formation = preload("res://src/formation.gd")
const Orientation = preload("res://src/orientation.gd")
const Order = preload("res://src/order.gd")
const T := Formation.Type

## Battalions farther than this from their place march there in column.
const COLUMN_DISTANCE := 300.0
## A battalion this close to its place counts as in it.
const STATION_SLACK := 25.0


## Acts on `o`. False if there is nothing left to command.
static func execute(sim, b, o) -> bool:
	var bns: Array = b.alive()
	if bns.is_empty():
		return false
	var ft: int = o.ftype if o.ftype >= 0 else _prevailing_ftype(bns)
	o.ftype = ft
	var dest: Vector2 = o.dest()
	if o.facing == null:
		var d := Orientation.decide(sim, b, dest, ft)
		o.facing = d.facing
		o.facing_reason = d.reason
	var facing: float = o.facing
	var slots: Array = sim.assign_slots(bns, dest, facing, ft)
	for k in bns.size():
		var f = bns[k]
		if f.detached:
			continue
		f.station = slots[k]
		f.station_facing = facing
		f.station_ftype = ft
		if not f.routing:
			_to_station(f)
	return true


## 1 Hz (staggered). Battalions that have rallied, or been pushed off their
## place, are sent back to it; the order is reported done once the whole
## brigade (bar any detached battalion) stands in its place.
static func think(sim, b) -> void:
	var o = b.order
	if o == null or o.status != Order.Status.EXECUTING:
		return
	var done := true
	for f in b.battalions:
		if f.dead or f.detached:
			continue
		if f.routing or f.has_target:
			done = false
		elif f.pos.distance_to(f.station) > STATION_SLACK or f.ftype != f.station_ftype:
			done = false
			if not f.engaged:
				_to_station(f)
	if done:
		sim.complete_order(b)


static func _to_station(f) -> void:
	f.target_pos = f.station
	f.target_facing = f.station_facing
	f.target_ftype = f.station_ftype
	f.has_target = true
	var far: bool = f.pos.distance_to(f.station) > COLUMN_DISTANCE
	f.march_ftype = T.COLUMN if far and f.station_ftype != T.MARCH else f.station_ftype


static func _prevailing_ftype(bns: Array) -> int:
	var counts := [0, 0, 0, 0]
	for f in bns:
		counts[f.ftype] += 1
	return counts.find(counts.max())
