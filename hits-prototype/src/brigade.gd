extends "res://src/command.gd"
## The lowest headquarters: commands battalions directly, receives orders by
## courier and lays its battalions out to carry them out (BattleSim._apply_order).

var id := 0
var row := 0
var battalions: Array = []
var pending: Array = []
var current = null
var awaiting := false
var ai_next := 0.0


func _init() -> void:
	level = Level.BRIGADE


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
