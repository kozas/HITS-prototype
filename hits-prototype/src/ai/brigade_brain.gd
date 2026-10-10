extends RefCounted
## The brigadier: turns the brigade's order into drill for its battalions.
## Today he knows MOVE: lay the battalions out at the destination in the ordered
## formation, on a front of his own choosing, and bring them there dressed in
## line. ATTACK and HOLD for the whole brigade, the skirmish screen, the second
## line and charges come with the next plan; the battalions already know how.
##
## Battalions detached by a superior's direct order are left alone.

const Formation = preload("res://src/formation.gd")
const Orientation = preload("res://src/orientation.gd")
const Order = preload("res://src/order.gd")
const BattalionBrain = preload("res://src/ai/battalion_brain.gd")

## A battalion this close to its place counts as in it.
const STATION_SLACK := 25.0
## Dressing: a battalion this far ahead of the rearmost halts for it; one
## within DRESS_EASY of it marches freely, and the rearmost steps out.
const DRESS_HALT := 15.0
const DRESS_EASY := 5.0
const DRESS_HURRY := 1.15


## Acts on `o`. False if there is nothing left to command.
static func execute(sim, b, o) -> bool:
	var bns: Array = []
	for f in b.alive():
		if not f.detached:
			bns.append(f)
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
		f.station = slots[k]
		f.station_facing = facing
		f.station_ftype = ft
		BattalionBrain.apply_standing(f, o.kind, o.intensity)
		BattalionBrain.apply_preferences(sim, f, o)
		if not f.routing:
			_to_station(sim, f)
	return true


## 1 Hz (staggered). Keeps the battalions dressed on one another as they
## advance, sends back to its place any that has rallied or been pushed off it,
## and reports the order done once the whole brigade stands in its place.
static func think(sim, b) -> void:
	var o = b.order
	if o == null or o.status != Order.Status.EXECUTING:
		for f in b.battalions:
			f.pace_mul = 1.0
		return
	_dress(b, o)
	var done := true
	for f in b.battalions:
		if f.dead or f.detached:
			continue
		if f.routing or f.morale_state == Formation.Morale.RALLYING or f.has_target:
			done = false
		elif f.pos.distance_to(f.station) > STATION_SLACK or f.ftype != f.station_ftype:
			done = false
			if not f.engaged:
				_to_station(sim, f)
	if done:
		sim.complete_order(b)


## Advance in step: measure how far each marching battalion still has to go
## along the brigade's front, and slow those that have got ahead of the
## rearmost (halting them if well ahead), so the line arrives together.
static func _dress(b, o) -> void:
	var fwd := Vector2(-sin(o.facing), -cos(o.facing))
	var marching := []
	var rearmost := -INF
	for f in b.battalions:
		f.pace_mul = 1.0
		if f.dead or f.detached or f.routing or not f.has_target or f.retiring:
			continue
		var remaining: float = (f.station - f.pos).dot(fwd)
		marching.append([f, remaining])
		rearmost = maxf(rearmost, remaining)
	if marching.size() < 2:
		return
	for m in marching:
		var ahead: float = rearmost - m[1]
		if ahead > DRESS_HALT:
			m[0].pace_mul = 0.0
		elif ahead > DRESS_EASY:
			m[0].pace_mul = 1.0 - (ahead - DRESS_EASY) / (DRESS_HALT - DRESS_EASY)
		elif ahead < 1.0 and rearmost > DRESS_EASY:
			m[0].pace_mul = DRESS_HURRY


static func _to_station(sim, f) -> void:
	BattalionBrain.march_to(sim, f, f.station, f.station_facing, f.station_ftype)


static func _prevailing_ftype(bns: Array) -> int:
	var counts := [0, 0, 0, 0]
	for f in bns:
		counts[f.ftype] += 1
	return counts.find(counts.max())
