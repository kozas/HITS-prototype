extends "res://src/command.gd"
## The lowest headquarters above the battalion: commands battalions directly,
## receives orders by courier and lays its battalions out to carry them out
## (BrigadeBrain).

var id := 0
var row := 0
var battalions: Array = []
var ai_next := 0.0


func _init() -> void:
	level = Level.BRIGADE


func add_battalion(f) -> void:
	add(f)
	battalions.append(f)


func battalions_all() -> Array:
	return battalions


func alive() -> Array:
	var out := []
	for f in battalions:
		if not f.dead:
			out.append(f)
	return out


func centroid() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for f in battalions:
		if not f.dead:
			c += f.center()
			n += 1
	return c / n if n > 0 else Vector2.ZERO


func position() -> Vector2:
	return centroid()
