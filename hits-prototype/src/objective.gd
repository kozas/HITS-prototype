extends RefCounted
## Where an order points: a place, a line, an area or a unit. Orders are intent
## around an objective; how to get there is the recipient's business. Today the
## map makes POINT and UNIT objectives; LINE and AREA are for the objective tool.

enum Kind { POINT, LINE, AREA, UNIT }

var kind: int = Kind.POINT
var p := Vector2.ZERO
var p2 := Vector2.ZERO  # LINE: the other end
var radius := 0.0       # AREA
var unit = null         # UNIT: a Command (usually an enemy battalion)


static func point(at: Vector2):
	var o = new()
	o.p = at
	return o


static func on_unit(u):
	var o = new()
	o.kind = Kind.UNIT
	o.unit = u
	o.p = u.position()
	return o


## The point the objective is about: where to go, or what to face.
func anchor() -> Vector2:
	match kind:
		Kind.LINE:
			return (p + p2) * 0.5
		Kind.UNIT:
			if unit != null and not unit.is_gone():
				p = unit.position()
			return p
		_:
			return p
