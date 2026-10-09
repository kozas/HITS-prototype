extends RefCounted
## Which way a unit fronts. Orders give a destination and a formation, never a
## facing: the commander on the spot turns his men toward the danger as he
## understands it. Every decision carries a reason so the map and dispatches can
## say why the unit faced the way it did.
##
## This is the seam for autonomous orientation. Today a brigade decides once,
## when it begins to carry out an order, from ground truth. Planned:
## - re-decide on the march and at the halt as threats appear or move
## - decide from the commander's own knowledge (seen or reported), not ground truth
## - refuse a flank against a second threat; use crests and reverse slopes
## - the same rules for corps, divisions and battalions

const Formation = preload("res://src/formation.gd")
const T := Formation.Type

## Enemy battalions within this distance of the destination draw the front.
const THREAT_RANGE := 1500.0
## Without a threat, moves shorter than this keep the present front.
const MIN_MARCH := 40.0

enum Reason { ENEMY, MARCH, HOLD }
const REASON_TEXT := ["facing the enemy", "facing the line of march", "keeping its front"]
const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


## {"facing": yaw, "reason": Reason} for brigade `b` forming `ftype` at `dest`.
## A march column always faces along the road it takes; other formations front
## the enemy if there is any near the destination.
static func decide(sim, b, dest: Vector2, ftype: int) -> Dictionary:
	if ftype != T.MARCH:
		var threat := threat_direction(sim, b.army, dest)
		if threat != Vector2.ZERO:
			return {"facing": yaw_of(threat), "reason": Reason.ENEMY}
	var march: Vector2 = dest - b.centroid()
	if march.length() > MIN_MARCH:
		return {"facing": yaw_of(march), "reason": Reason.MARCH}
	return {"facing": current_front(b), "reason": Reason.HOLD}


## Direction of the enemy as seen from `p`: each formed enemy battalion in range
## pulls with its strength over distance squared, so the nearest dominate.
## ZERO if there is none.
static func threat_direction(sim, army: int, p: Vector2) -> Vector2:
	var sum := Vector2.ZERO
	for e in sim.formations:
		if e.dead or e.routing or e.army == army:
			continue
		var to: Vector2 = e.cpos - p
		var d := to.length()
		if d > THREAT_RANGE or d < 1.0:
			continue
		sum += to / d * e.strength / (d * d)
	return sum.normalized()


## The brigade's present front: the mean of its battalions' facings.
static func current_front(b) -> float:
	var sum := Vector2.ZERO
	for f in b.alive():
		sum += f.forward()
	return yaw_of(sum) if sum != Vector2.ZERO else 0.0


static func yaw_of(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


## "facing the enemy (NNE)"-style text, for the map and dispatches.
static func describe(facing: float, reason: int) -> String:
	return "%s (%s)" % [REASON_TEXT[reason], compass(facing)]


## Yaw 0 faces north (-Z) and yaw grows anticlockwise, so east is -PI/2.
static func compass(facing: float) -> String:
	return COMPASS[posmod(roundi(-facing / (PI / 4.0)), 8)]
