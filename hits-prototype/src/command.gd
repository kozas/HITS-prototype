extends RefCounted
## One headquarters in the chain of command: army, corps, division or brigade.
## Brigades (brigade.gd) also hold their battalions and their current orders;
## for now the levels above only group their subordinates. In M1 they will
## receive orders themselves and pass them down, each adding its own delay.

enum Level { ARMY, CORPS, DIVISION, BRIGADE }

var level: int = Level.ARMY
var army := 0
var title := ""      # unit name, e.g. "IIe Corps", "Brigade Durand"
var label := ""      # short form for the map and dispatches
var commander := ""  # e.g. "Général de division Moreau"
var parent = null
var subordinates: Array = []


func add(sub) -> void:
	sub.parent = self
	subordinates.append(sub)


## Every battalion under this command, including dead ones.
func battalions_all() -> Array:
	var out := []
	for s in subordinates:
		out.append_array(s.battalions_all())
	return out


func strength() -> int:
	var n := 0
	for f in battalions_all():
		if not f.dead:
			n += f.strength
	return n
