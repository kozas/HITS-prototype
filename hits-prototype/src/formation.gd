extends "res://src/command.gd"
## One battalion: the atom of the simulation, and the bottom of the chain of
## command (it can take orders like any other Command).
## Individual soldiers have no CPU state at all; soldier.gdshader derives every
## man, officer and drummer from these fields. footprint_for() and colour_pos()
## must mirror the shader's battalion geometry (bn_make / bn_size / staff_pos).

enum Type { LINE, COLUMN, SQUARE, MARCH }
const TYPE_NAMES := ["Line", "Column", "Square", "March"]

const FILE_W := 0.6
const RANK_D := 0.65
const SERRE := 1.3
const GUARD_W := 1.2
const ORDINARY_STEP := 0.82  # pas ordinaire: 76 paces/min of 0.65 m
const QUICK_STEP := 1.08     # pas accéléré: 100 paces/min

var id := 0         # index in BattleSim.formations
var brigade := 0    # index in BattleSim.brigades (also `parent`)
# label: short, e.g. "1/45e"; title: e.g. "1er bataillon, 45e de Ligne"
var strength := 600
var max_strength := 600
var ranks := 3
var companies := 6

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
## Its place in the brigade, as last laid out by the brigadier.
var station := Vector2.ZERO
var station_facing := 0.0
var station_ftype: int = Type.LINE
var moving := false
var moving_since := -1000.0  # guides step out ahead when the battalion advances
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


func _init() -> void:
	level = Level.BATTALION


func battalions_all() -> Array:
	return [self]


func position() -> Vector2:
	return cpos


func is_gone() -> bool:
	return dead


func refresh_shape() -> void:
	fp = footprint_as(ftype)


func footprint_as(type: int) -> Vector2:
	return footprint_for(type, strength, ranks, companies)


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
	trans_dur = transition_time(ftype_from, ftype)
	render_dirty = true


## Lines advance at the ordinary step; columns manoeuvre at the quick step.
func speed() -> float:
	if routing:
		return 2.4
	match ftype:
		Type.LINE:
			return ORDINARY_STEP
		Type.COLUMN, Type.MARCH:
			return QUICK_STEP
		_:
			return 0.15


## A wheel can go no faster than the outer flank can march at the quick step:
## about 1 degree a second for a battalion in line.
func turn_rate() -> float:
	return minf(QUICK_STEP / maxf(fp.x * 0.5, 1.0), deg_to_rad(15.0))


## Muskets that can bear on a target to the front (front two ranks).
func firing_muskets() -> int:
	match ftype:
		Type.LINE, Type.COLUMN:
			return mini(strength, int(fp.x / FILE_W) * 2)
		Type.SQUARE:
			return strength / 8
		_:
			return 0


## How long a change of formation takes: the farthest section marches from its
## old place to its new one at the quick step (as the shader animates it).
func transition_time(a: int, b: int) -> float:
	var fa := footprint_as(a)
	var fb := footprint_as(b)
	return 3.0 + Vector2(absf(fa.x - fb.x) * 0.5, maxf(fa.y, fb.y)).length() / QUICK_STEP


## (width, depth) in metres; the anchor is the centre of the front rank.
## Mirrors bn_make / bn_size in soldier.gdshader.
static func footprint_for(type: int, n: int, rk: int, c: int) -> Vector2:
	var g := _geom(n, rk, c)
	match type:
		Type.LINE:
			return Vector2(c * g.x + GUARD_W, g.y)
		Type.COLUMN:
			return Vector2(2.0 * g.x + GUARD_W, (c / 2 - 1) * maxf(0.5 * g.x, g.y + 2.0) + g.y)
		Type.SQUARE:
			return Vector2(2.0 * g.x, 2.0 * rk * RANK_D + maxi(c / 2 - 2, 0) * g.x)
		_:
			return Vector2(g.z, (2 * c - 1) * maxf(g.z, g.y + 3.0) + g.y)


## Where the colours stand (local x, z), in the middle of the colour guard.
func colour_pos(type: int) -> Vector2:
	var g := _geom(strength, ranks, companies)
	match type:
		Type.SQUARE:
			return Vector2(0, footprint_as(type).y * 0.5 - 1.0 + RANK_D)
		Type.MARCH:
			return Vector2(0, 2.0 * maxf(g.z, g.y + 3.0) - 2.5 + RANK_D)
		_:
			return Vector2(0, RANK_D)


## (company frontage incl. the captain's file, company depth, 1st section frontage)
static func _geom(n: int, rk: int, c: int) -> Vector3:
	var pc := maxi((maxi(n, 1) + c - 1) / c, 1)
	var nf := maxi((pc + rk - 1) / rk, 1)
	return Vector3((nf + 1) * FILE_W, rk * RANK_D + SERRE, (nf - nf / 2) * FILE_W)
