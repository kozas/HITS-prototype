extends Control
## The general's map. Your own brigades are drawn where they are (M1: where
## they were last *reported*). The enemy is drawn where you last saw him,
## fading with age.
## Wheel zooms at the cursor; drag with the left (on empty ground) or middle
## button to pan. Writing an order: left-click a brigade, right-click its
## destination, choose the formation it is to take there in the popup, then
## Issue (Enter). Only then does a courier ride. Orders carry no facing: the
## brigade fronts as it sees fit when it acts (Orientation).

const Formation = preload("res://src/formation.gd")
const Orientation = preload("res://src/orientation.gd")
const T := Formation.Type
const ZOOM_RANGE := Vector2(1.0, 16.0)
const INK := Color(0.1, 0.1, 0.2)
const PARCHMENT := Color(0.95, 0.9, 0.75)
const DRAFT := Color(0.3, 1, 0.3)
const STATUS_TEXT := {"riding": "courier riding", "staff": "preparing", "executing": ""}
const STATUS_COLOUR := {"riding": Color(1, 0.85, 0.2), "staff": Color(1, 0.5, 0.1), "executing": Color(1, 1, 1, 0.8)}

var main
var sim
var terrain
var selected := -1
var zoom := 1.0
var view_center := Vector2.ZERO  # world (x, z) at the centre of the screen
var _relief: ColorRect
var _panning := false
var _font: Font

# The order being written: destination and formation, not yet sent.
var _has_draft := false
var _draft_dest := Vector2.ZERO
var _draft_ftype: int = T.LINE
var _draft_facing := 0.0  # the front the brigade would choose if it acted now
var _popup: PanelContainer
var _popup_title: Label
var _popup_front: Label
var _ftype_buttons: Array = []


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
	_build_popup()
	# An unsent order doesn't survive folding the map away.
	visibility_changed.connect(func() -> void:
		if not visible:
			cancel_draft())


## The order popup: formation, the front the brigade is likely to take, and
## Issue / Cancel. It sits beside the destination and follows it as the map moves.
func _build_popup() -> void:
	_popup = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.08, 0.065, 0.94)
	style.border_color = Color(0.4, 0.34, 0.24)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_popup.add_theme_stylebox_override("panel", style)
	_popup.visible = false
	add_child(_popup)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_popup.add_child(col)
	_popup_title = _popup_label(col, 15)
	var row := HBoxContainer.new()
	col.add_child(row)
	var group := ButtonGroup.new()
	for t in Formation.TYPE_NAMES.size():
		var btn := Button.new()
		btn.text = "%d  %s" % [t + 1, Formation.TYPE_NAMES[t]]
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(set_draft_ftype.bind(t))
		row.add_child(btn)
		_ftype_buttons.append(btn)
	_popup_front = _popup_label(col, 13)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(actions)
	var cancel := Button.new()
	cancel.text = "Cancel (Esc)"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(cancel_draft)
	actions.add_child(cancel)
	var issue := Button.new()
	issue.text = "Issue order (Enter)"
	issue.focus_mode = Control.FOCUS_NONE
	issue.pressed.connect(issue_draft)
	actions.add_child(issue)


func _popup_label(parent: Control, sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	parent.add_child(l)
	return l


func _process(_dt: float) -> void:
	if not visible:
		return
	if _has_draft:
		_update_draft()
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


# ---------------------------------------------------------------- orders

func select(brigade_id: int) -> void:
	if brigade_id != selected:
		cancel_draft()
	selected = brigade_id


func has_draft() -> bool:
	return _has_draft


## Right-click: start an order for the selected brigade, or move the
## destination of the one being written (keeping its formation).
func _set_draft_dest(world: Vector2) -> void:
	if not _has_draft:
		_has_draft = true
		set_draft_ftype(_prevailing_ftype(sim.brigades[selected]))
	_draft_dest = world
	_popup.visible = true
	_update_draft()


func set_draft_ftype(t: int) -> void:
	_draft_ftype = t
	_ftype_buttons[t].button_pressed = true


func cancel_draft() -> void:
	_has_draft = false
	if _popup:
		_popup.visible = false


## Seal the order and hand it to a courier.
func issue_draft() -> void:
	if not _has_draft:
		return
	main.issue_player_order(selected, _draft_dest, _draft_ftype)
	cancel_draft()


func _update_draft() -> void:
	var b = sim.brigades[selected]
	if b.alive().is_empty():
		cancel_draft()
		return
	var plan := Orientation.decide(sim, b, _draft_dest, _draft_ftype)
	_draft_facing = plan.facing
	var dist: float = b.centroid().distance_to(_draft_dest)
	_popup_title.text = "%s: march %s, then form" % [b.title, _distance_text(dist)]
	_popup_front.text = "Front at the brigade's discretion: likely %s" % Orientation.describe(plan.facing, plan.reason)
	# Beside the destination, flipped to the other side near the map's edges.
	_popup.reset_size()
	var s := _popup.size
	var anchor := to_px(_draft_dest)
	var p := anchor + Vector2(18, 18)
	if p.x + s.x > size.x - 8.0:
		p.x = anchor.x - 18.0 - s.x
	if p.y + s.y > size.y - 8.0:
		p.y = anchor.y - 18.0 - s.y
	_popup.position = p.clamp(Vector2(8, 60), (size - s - Vector2(8, 8)).max(Vector2(8, 60)))


## The formation most of the brigade's battalions are in now.
func _prevailing_ftype(b) -> int:
	var counts := [0, 0, 0, 0]
	for f in b.alive():
		counts[f.ftype] += 1
	return counts.find(counts.max())


static func _distance_text(m: float) -> String:
	return ("%d m" % (roundi(m / 10.0) * 10)) if m < 1000.0 else ("%.1f km" % (m / 1000.0))


# ---------------------------------------------------------------- drawing

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
		if not STATUS_COLOUR.has(st):
			continue
		var b = sim.brigades[o.brigade]
		if st == "executing" and not _any_moving(b):
			o.status = "complete"
			continue
		# Until the brigade acts on it, the order has no front: only the brigade decides that.
		_draw_order(b.centroid(), o.dest, o.facing, STATUS_COLOUR[st], st == "riding")
		var text: String = Formation.TYPE_NAMES[o.ftype]
		if STATUS_TEXT[st] != "":
			text += ", " + STATUS_TEXT[st]
		draw_string(_font, to_px(o.dest) + Vector2(10, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)

	for c in main.couriers.couriers:
		if c.army == main.PLAYER_ARMY:
			draw_circle(to_px(c.pos), 3.5, Color(1, 0.85, 0.2))

	if _has_draft:
		_draw_draft()

	var pp: Vector2 = main.player_xz()
	var pyaw: float = main.player.yaw
	var fwd := Vector2(-sin(pyaw), -cos(pyaw))
	var pts := PackedVector2Array([to_px(pp) + fwd * 10, to_px(pp) + fwd.rotated(2.5) * 7, to_px(pp) + fwd.rotated(-2.5) * 7])
	draw_colored_polygon(pts, Color.WHITE)

	_draw_scale_bar()
	var help := "MAP  |  %s  |  wheel zoom, drag pan  |  LMB select brigade  |  RMB destination, then formation [1-4] and Issue [Enter]  |  Esc cancel" % main.clock_text()
	draw_string(_font, Vector2(16, 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PARCHMENT)
	var sel := "Selected: %s" % (sim.brigades[selected].title if selected >= 0 else "none (left-click a brigade)")
	draw_string(_font, Vector2(16, 44), sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PARCHMENT)


## The order being written: the route, and a ghost of the brigade as it would
## stand at the destination in the chosen formation, on the front it would
## likely choose.
func _draw_draft() -> void:
	var b = sim.brigades[selected]
	var bns: Array = b.alive()
	var slots: Array = sim.assign_slots(bns, _draft_dest, _draft_facing, _draft_ftype)
	for k in bns.size():
		var pts := _block_pts(slots[k], _draft_facing, bns[k].footprint_as(_draft_ftype))
		pts.append(pts[0])
		draw_polyline(pts, DRAFT, 1.5)
	draw_line(to_px(b.centroid()), to_px(_draft_dest), DRAFT, 2.0)
	draw_circle(to_px(_draft_dest), 4.0, DRAFT)


## A round-numbered scale bar of 80-200 px in the bottom-left corner.
func _draw_scale_bar() -> void:
	var metres := 50.0
	for m in [50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0]:
		metres = m
		if m * px_per_m() >= 80.0:
			break
	var length := metres * px_per_m()
	var o := Vector2(24, size.y - 28)
	draw_rect(Rect2(o - Vector2(8, 22), Vector2(length + 16, 34)), Color(PARCHMENT, 0.8))
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


## Screen corners of a formation's footprint: front-left, front-right,
## rear-right, rear-left. `p` is the anchor (centre of the front rank).
func _block_pts(p: Vector2, yaw: float, fp: Vector2) -> PackedVector2Array:
	var rt := Vector2(cos(yaw), -sin(yaw))
	var bk := Vector2(sin(yaw), cos(yaw))
	# Never smaller than 2.5 px, so battalions stay visible fully zoomed out.
	var w := maxf(fp.x, 2.5 / px_per_m())
	var d := maxf(fp.y, 2.5 / px_per_m())
	return PackedVector2Array([
		to_px(p - rt * w * 0.5), to_px(p + rt * w * 0.5),
		to_px(p + rt * w * 0.5 + bk * d), to_px(p - rt * w * 0.5 + bk * d),
	])


func _draw_block(p: Vector2, yaw: float, fp: Vector2, col: Color) -> void:
	var pts := _block_pts(p, yaw, fp)
	draw_colored_polygon(pts, col)
	draw_line(pts[0], pts[1], col.darkened(0.5), 1.5)


## Route and destination. `facing` is null until the brigade has chosen its
## front; then the destination shows the front and which way it faces.
func _draw_order(from: Vector2, dest: Vector2, facing, col: Color, dashed: bool) -> void:
	var a := to_px(from)
	var b := to_px(dest)
	if dashed:
		draw_dashed_line(a, b, col, 2.0, 6.0)
	else:
		draw_line(a, b, col, 2.0)
	if facing == null:
		draw_arc(b, 6.0, 0, TAU, 16, col, 2.0)
		return
	var fwd := Vector2(-sin(facing), -cos(facing))
	var rt := Vector2(cos(facing), -sin(facing))
	draw_line(b - rt * 14, b + rt * 14, col, 3.0)
	draw_line(b, b + fwd * 12, col, 2.0)


# ---------------------------------------------------------------- input

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
						select(picked)
					else:
						_panning = true
				else:
					_panning = false
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and selected >= 0:
					_set_draft_dest(to_world(mb.position))
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_center -= mm.relative / px_per_m()
			_clamp_view()
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
