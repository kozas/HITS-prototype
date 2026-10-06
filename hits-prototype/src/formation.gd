extends RefCounted
## One battalion: the atom of the simulation.
## Individual soldiers have no CPU state at all; soldier.gdshader derives every
## man from these fields. footprint_for() must mirror the shader's slot layouts.

enum Type { LINE, COLUMN, SQUARE, MARCH }
const TYPE_NAMES := ["Line", "Column", "Square", "March"]

const FILE_W := 0.62
const RANK_D := 0.85
const COLUMN_FILES := 48
const MARCH_FILES := 6

var id := 0
var army := 0
var brigade := 0
var label := ""
var strength := 600
var max_strength := 600
var ranks := 3

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
var moving := false
var slope_factor := 1.0

var morale := 1.0
var routing := false
var rout_amount := 0.0
var engaged := false
var threat_dir := Vector2.ZERO
var last_volley := -1000.0
var next_fire := 0.0
var broken := false
var broken_at := 0.0
var dead := false
var cpos := Vector2.ZERO  # cached center(), refreshed every sim tick

# What the player knows about this formation (enemy side): drives the map.
var los_visible := true
var seen_time := -1.0e9
var seen_pos := Vector2.ZERO
var seen_facing := 0.0
var seen_ftype := 0

var render_dirty := true
var fp := Vector2.ONE  # cached footprint; refresh_shape() when type or strength change


func refresh_shape() -> void:
	fp = footprint_for(ftype, strength, ranks)


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
	trans_dur = transition_time(ftype_from, new_type)
	render_dirty = true


func speed() -> float:
	if routing:
		return 2.4
	match ftype:
		Type.LINE:
			return 0.7
		Type.COLUMN:
			return 1.0
		Type.MARCH:
			return 1.25
		_:
			return 0.15


func turn_rate() -> float:
	match ftype:
		Type.LINE:
			return deg_to_rad(2.5)
		Type.COLUMN:
			return deg_to_rad(10.0)
		Type.MARCH:
			return deg_to_rad(15.0)
		_:
			return deg_to_rad(4.0)


## Muskets that can bear on a target to the front.
func firing_muskets() -> int:
	var fp := footprint()
	match ftype:
		Type.LINE:
			return mini(strength, int(fp.x / FILE_W) * 2)
		Type.COLUMN:
			return mini(strength, COLUMN_FILES * 2)
		Type.SQUARE:
			return strength / 8
		_:
			return 0


static func transition_time(a: int, b: int) -> float:
	if b == Type.SQUARE:
		return 25.0 if a == Type.COLUMN else 50.0
	if a == Type.MARCH or b == Type.MARCH:
		return 35.0
	return 45.0


## (width, depth) in metres. Mirrors soldier.gdshader slot_* functions.
static func footprint_for(type: int, n: int, rk: int) -> Vector2:
	n = maxi(n, 1)
	match type:
		Type.LINE:
			var files := (n + rk - 1) / rk
			return Vector2(files * FILE_W, rk * RANK_D)
		Type.COLUMN:
			var cf := mini(n, COLUMN_FILES)
			var rows := (n + cf - 1) / cf
			return Vector2(cf * FILE_W, rows * RANK_D + (rows / 3) * 2.4)
		Type.SQUARE:
			var fpf := maxi(((n + 3) / 4 + 3) / 4, 1)
			var side := fpf * FILE_W + 8.0 * RANK_D
			return Vector2(side, side)
		_:
			var rows := (n + MARCH_FILES - 1) / MARCH_FILES
			return Vector2(MARCH_FILES * 0.7, rows * 1.1)
