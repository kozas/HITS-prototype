extends Control
## The general's map. Your own brigades are drawn where they are (M1: where
## they were last *reported*). The enemy is drawn where you last saw him,
## fading with age.
## Left-click a brigade to select it. Right-drag from the destination to set the
## facing. 1-4 picks the formation. Releasing the drag writes the order and a
## courier rides off with it.

const Formation = preload("res://src/formation.gd")
const T := Formation.Type

var main
var sim
var terrain
var relief: Texture2D
var selected := -1
var order_ftype: int = T.LINE
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_cur := Vector2.ZERO
var _side := 1.0
var _origin := Vector2.ZERO
var _font: Font


func setup(m) -> void:
	main = m
	sim = m.sim
	terrain = m.terrain
	relief = terrain.make_relief(256)
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func to_px(w: Vector2) -> Vector2:
	return _origin + (w + Vector2.ONE * terrain.SIZE * 0.5) / terrain.SIZE * _side


func to_world(p: Vector2) -> Vector2:
	return (p - _origin) / _side * terrain.SIZE - Vector2.ONE * terrain.SIZE * 0.5


func _draw() -> void:
	_side = minf(size.x, size.y) * 0.94
	_origin = (size - Vector2(_side, _side)) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.05, 0.92))
	draw_texture_rect(relief, Rect2(_origin, Vector2(_side, _side)), false)
	var now: float = sim.time

	for f in sim.formations:
		if f.dead:
			continue
		var col: Color
		var p: Vector2
		var yaw: float
		var ft: int
		if f.army == main.PLAYER_ARMY:
			col = Color(0.15, 0.2, 0.65)
			p = f.pos
			yaw = f.facing
			ft = f.ftype
			if f.routing:
				col = Color(0.55, 0.55, 0.8)
		else:
			var age: float = now - f.seen_time
			if age > 1800.0:
				continue
			col = Color(0.75, 0.1, 0.08, clampf(1.0 - age / 1800.0, 0.25, 1.0))
			p = f.seen_pos
			yaw = f.seen_facing
			ft = f.seen_ftype
		_draw_block(p, yaw, Formation.footprint_for(ft, f.strength, f.ranks), col)

	for b in sim.brigades:
		if b.army != main.PLAYER_ARMY or b.alive().is_empty():
			continue
		var c := to_px(b.centroid())
		if b.id == selected:
			draw_arc(c, 22.0, 0, TAU, 32, Color(1, 0.85, 0.2), 2.0)
		draw_string(_font, c + Vector2(-20, -14), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.1, 0.2))

	for o in main.player_orders:
		var st: String = o.status
		if st == "riding" or st == "staff" or st == "executing":
			var b = sim.brigades[o.brigade]
			if st == "executing" and not _any_moving(b):
				o.status = "complete"
				continue
			var col: Color = {"riding": Color(1, 0.85, 0.2), "staff": Color(1, 0.5, 0.1), "executing": Color(1, 1, 1, 0.8)}[st]
			_draw_order(b.centroid(), o.dest, o.facing, col, st == "riding")

	for c in main.couriers.couriers:
		if c.army == main.PLAYER_ARMY:
			draw_circle(to_px(c.pos), 3.5, Color(1, 0.85, 0.2))

	var pp: Vector2 = main.player_xz()
	var pyaw: float = main.player.yaw
	var fwd := Vector2(-sin(pyaw), -cos(pyaw))
	var pts := PackedVector2Array([to_px(pp) + fwd * 10, to_px(pp) + fwd.rotated(2.5) * 7, to_px(pp) + fwd.rotated(-2.5) * 7])
	draw_colored_polygon(pts, Color.WHITE)

	if _dragging and selected >= 0:
		var d := _drag_cur - _drag_start
		var facing: float = atan2(-d.x, -d.y) if d.length() > 30.0 else _default_facing(_drag_start)
		_draw_order(sim.brigades[selected].centroid(), _drag_start, facing, Color(0.3, 1, 0.3), false)

	var help := "MAP  |  %s  |  LMB select brigade  |  RMB drag: destination -> facing  |  formation: [1] Line [2] Column [3] Square [4] March = %s" % [main.clock_text(), Formation.TYPE_NAMES[order_ftype]]
	draw_string(_font, Vector2(16, 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.75))
	var sel := "Selected: %s" % (sim.brigades[selected].label if selected >= 0 else "none")
	draw_string(_font, Vector2(16, 44), sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.75))


func _any_moving(b) -> bool:
	for f in b.alive():
		if f.has_target:
			return true
	return false


func _draw_block(p: Vector2, yaw: float, fp: Vector2, col: Color) -> void:
	var rt := Vector2(cos(yaw), -sin(yaw))
	var bk := Vector2(sin(yaw), cos(yaw))
	var w := maxf(fp.x, 14.0)
	var d := maxf(fp.y, 14.0)
	var pts := PackedVector2Array([
		to_px(p - rt * w * 0.5), to_px(p + rt * w * 0.5),
		to_px(p + rt * w * 0.5 + bk * d), to_px(p - rt * w * 0.5 + bk * d),
	])
	draw_colored_polygon(pts, col)
	draw_line(pts[0], pts[1], col.darkened(0.5), 1.5)


func _draw_order(from: Vector2, dest: Vector2, facing: float, col: Color, dashed: bool) -> void:
	var a := to_px(from)
	var b := to_px(dest)
	if dashed:
		draw_dashed_line(a, b, col, 2.0, 6.0)
	else:
		draw_line(a, b, col, 2.0)
	var fwd := Vector2(-sin(facing), -cos(facing))
	var rt := Vector2(cos(facing), -sin(facing))
	draw_line(b - rt * 14, b + rt * 14, col, 3.0)
	draw_line(b, b + fwd * 12, col, 2.0)


func _default_facing(dest: Vector2) -> float:
	var b = sim.brigades[selected]
	var d: Vector2 = dest - b.centroid()
	if d.length() < 30.0:
		return b.alive()[0].facing
	return atan2(-d.x, -d.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			selected = _pick_brigade(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and selected >= 0:
			if mb.pressed:
				_dragging = true
				_drag_start = to_world(mb.position)
				_drag_cur = _drag_start
			elif _dragging:
				_dragging = false
				var d := _drag_cur - _drag_start
				var facing: float = atan2(-d.x, -d.y) if d.length() > 30.0 else _default_facing(_drag_start)
				main.issue_player_order(selected, _drag_start, facing, order_ftype)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_cur = to_world((event as InputEventMouseMotion).position)
		accept_event()


func _pick_brigade(p: Vector2) -> int:
	var best := -1
	var bd := 16.0
	for f in sim.formations:
		if f.dead or f.army != main.PLAYER_ARMY:
			continue
		var d := to_px(f.cpos).distance_to(p)
		if d < bd:
			bd = d
			best = f.brigade
	return best
