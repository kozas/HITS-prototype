extends RefCounted
## One node in the chain of command: army, corps, division, brigade or
## battalion. Any of them can receive an Order (order.gd). Each level's brain
## (src/ai/) turns its current order into orders for its subordinates or, at the
## bottom, into drill. Command itself holds only data.

enum Level { ARMY, CORPS, DIVISION, BRIGADE, BATTALION }

## Seconds of staff work between an order arriving and the HQ acting on it
## (reading, deciding, passing it down), before the commander's skill.
const STAFF_DELAY := [[120.0, 300.0], [60.0, 180.0], [40.0, 120.0], [20.0, 75.0], [5.0, 15.0]]

var level: int = Level.ARMY
var army := 0
var title := ""      # unit name, e.g. "IIe Corps", "Brigade Durand"
var label := ""      # short form for the map and dispatches
var commander := ""  # e.g. "Général de division Moreau"
var parent = null
var subordinates: Array = []

## The commander's character, 0..1 each. Skill shortens staff work; the others
## are for the brains to weigh (initiative to act unbidden, aggression to press
## an attack, caution to keep a reserve and fall back early).
var initiative := 0.5
var aggression := 0.5
var caution := 0.5
var skill := 0.5

var order = null     # the Order being carried out
var inbox: Array = []  # Orders delivered, waiting out the staff work
var awaiting := false  # a courier is on his way with an order
## Acting on an order from above its own commander: the parent leaves it be
## until that order is done.
var detached := false


func add(sub) -> void:
	sub.parent = self
	subordinates.append(sub)


## Every battalion under this command, including dead ones.
func battalions_all() -> Array:
	var out := []
	for s in subordinates:
		out.append_array(s.battalions_all())
	return out


## Men under arms (a battalion's own count is its `strength`).
func men() -> int:
	var n := 0
	for f in battalions_all():
		if not f.dead:
			n += f.strength
	return n


## Where the commander is to be found: couriers ride here. For now an HQ sits
## at the centre of its troops.
func position() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for f in battalions_all():
		if not f.dead:
			c += f.cpos
			n += 1
	return c / n if n > 0 else Vector2.ZERO


## No longer a fighting unit (every battalion dead or dispersed).
func is_gone() -> bool:
	for f in battalions_all():
		if not f.dead:
			return false
	return true


func staff_delay(rng: RandomNumberGenerator) -> float:
	var r: Array = STAFF_DELAY[level]
	return rng.randf_range(r[0], r[1]) * lerpf(1.3, 0.7, skill)


func roll_personality(rng: RandomNumberGenerator) -> void:
	initiative = rng.randf()
	aggression = rng.randf()
	caution = rng.randf()
	skill = rng.randf_range(0.2, 0.9)
