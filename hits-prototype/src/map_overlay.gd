extends Control
## The general's map. Your own brigades are drawn where they are (M1: where
## they were last *reported*). The enemy is drawn where you last saw him,
## fading with age.
## Wheel zooms at the cursor; drag with the left (on empty ground) or middle
## button to pan. Left-click a brigade to select it. Right-drag from the
## destination to set the facing. 1-4 picks the formation. Releasing the drag
## writes the order and a courier rides off with it.

const Formation = preload("res://src/formation.gd")
const T := Formation.Type
const ZOOM_RANGE := Vector2(1.0, 16.0)
const INK := Color(0.1, 0.1, 0.2)

var main
var sim
var terrain
var selected := -1
var order_ftype: int = T.LINE
var zoom := 1.0
var view_center := Vector2.ZERO  # world (x, z) at the centre of the screen
var _relief: ColorRect
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_cur := Vector2.ZERO
var _panning := false
var _font: Font


func setup(m) -> void:
	main = m
	sim = m.sim
	terrain = m.terrain
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# The ground is a shader over the heightmap, drawn behind the map's ink.
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/map_relief.gdshader")
	terrain.apply_height_params(mat)
	_relief = ColorRect.new()
	_relief.material = mat
	_relief.show_behind_parent = true
	_relief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relief.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_relief)


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Centre the map on a point at a given zoom (used by the order of battle).
func focus(world: Vector2, z: float) -> void:
	zoom = clampf(z, ZOOM_RANGE.x, ZOOM_RANGE.y)
	view_center = world
	_clamp_view()


func px_per_m() -> float:
	return minf(size.x, size.y) * 0.94 / terrain.SIZE * zoom


func to_px(w: Vector2) -> Vector2:
	return size * 0.5 + (w - view_center) * px_per_m()


func to_world(p: Vector2) -> Vector2:
	return view_center + (p - size * 0.5) / px_per_m()


func _clamp_view() -> void:
	var h: float = terrain.SIZE * 0.5
	view_center = view_center.clamp(Vector2(-h, -h), Vector2(h, h))


func _draw() -> void:
	var mat := _relief.material as ShaderMaterial
	mat.set_shader_parameter("view_center", view_center)
	mat.set_shader_parameter("px_per_m", px_per_m())
	mat.set_shader_parameter("rect_size", size)
	var now: float = sim.time
	var labels := zoom >= 4.0

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
		_draw_block(p, yaw, f.footprint_as(ft), col)
		if labels:
			draw_string(_font, to_px(p) + Vector2(4, -4), f.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.darkened(0.4))

	for b in sim.brigades:
		if b.army != main.PLAYER_ARMY or b.alive().is_empty():
			continue
		var c := to_px(b.centroid())
		if b.id == selected:
			draw_arc(c, 22.0, 0, TAU, 32, Color(1, 0.85, 0.2), 2.0)
		draw_string(_font, c + Vector2(-20, -14 - (10 if labels else 0)), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)

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

	_draw_scale_bar()
	var help := "MAP  |  %s  |  wheel zoom, drag pan  |  LMB select brigade  |  RMB drag: destination -> facing  |  formation: [1] Line [2] Column [3] Square [4] March = %s" % [main.clock_text(), Formation.TYPE_NAMES[order_ftype]]
	draw_string(_font, Vector2(16, 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.75))
	var sel := "Selected: %s" % (sim.brigades[selected].title if selected >= 0 else "none")
	draw_string(_font, Vector2(16, 44), sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.75))


## A round-numbered scale bar of 80-200 px in the bottom-left corner.
func _draw_scale_bar() -> void:
	var metres := 50.0
	for m in [50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0]:
		metres = m
		if m * px_per_m() >= 80.0:
			break
	var length := metres * px_per_m()
	var o := Vector2(24, size.y - 28)
	draw_rect(Rect2(o - Vector2(8, 22), Vector2(length + 16, 34)), Color(0.95, 0.9, 0.75, 0.8))
	draw_line(o, o + Vector2(length, 0), INK, 3.0)
	draw_line(o + Vector2(0, -5), o + Vector2(0, 5), INK, 2.0)
	draw_line(o + Vector2(length, -5), o + Vector2(length, 5), INK, 2.0)
	var text := ("%d m" % metres) if metres < 1000.0 else ("%d km" % int(metres / 1000.0))
	draw_string(_font, o + Vector2(0, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)


func _any_moving(b) -> bool:
	for f in b.alive():
		if f.has_target:
			return true
	return false


func _draw_block(p: Vector2, yaw: float, fp: Vector2, col: Color) -> void:
	var rt := Vector2(cos(yaw), -sin(yaw))
	var bk := Vector2(sin(yaw), cos(yaw))
	# Never smaller than 2.5 px, so battalions stay visible fully zoomed out.
	var w := maxf(fp.x, 2.5 / px_per_m())
	var d := maxf(fp.y, 2.5 / px_per_m())
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
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					# Zoom about the cursor: the point under it stays put.
					var before := to_world(mb.position)
					zoom = clampf(zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_RANGE.x, ZOOM_RANGE.y)
					view_center += before - to_world(mb.position)
					_clamp_view()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var picked := _pick_brigade(mb.position)
					if picked >= 0:
						selected = picked
					else:
						_panning = true
				else:
					_panning = false
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if selected >= 0:
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
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_center -= mm.relative / px_per_m()
			_clamp_view()
		if _dragging:
			_drag_cur = to_world(mm.position)
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
