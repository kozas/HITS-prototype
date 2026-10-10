extends Control
## The general's map. Your own troops are drawn where they are (M1: where they
## were last *reported*). The enemy is drawn where you last saw him, fading with
## age.
## Wheel zooms at the cursor; drag with the left (on empty ground) or middle
## button to pan.
## Writing an order: left-click a brigade (click it again, or zoom in, for one
## of its battalions), right-click where it is to go (or an enemy unit, to
## attack it), fill in the order sheet, then Issue (Enter). Only then does a
## courier ride. Orders carry no facing: the unit fronts as it sees fit when it
## acts (Orientation). A battalion ordered directly is detached from its
## brigade until the order is done (or it is told to rejoin).

const Formation = preload("res://src/formation.gd")
const Command = preload("res://src/command.gd")
const Orientation = preload("res://src/orientation.gd")
const Order = preload("res://src/order.gd")
const Objective = preload("res://src/objective.gd")
const Doctrine = preload("res://src/ai/doctrine.gd")
const T := Formation.Type
const ZOOM_RANGE := Vector2(1.0, 16.0)
## Zoomed in this far, a click picks the battalion rather than its brigade.
const BATTALION_ZOOM := 6.0
const INK := Color(0.1, 0.1, 0.2)
const PARCHMENT := Color(0.95, 0.9, 0.75)
const DRAFT := Color(0.3, 1, 0.3)
const SELECT := Color(1, 0.85, 0.2)
const DETACHED := Color(1.0, 0.55, 0.1)
const STATUS_TEXT := {Order.Status.RIDING: "courier riding", Order.Status.PREPARING: "preparing", Order.Status.EXECUTING: ""}
const STATUS_COLOUR := {Order.Status.RIDING: Color(1, 0.85, 0.2), Order.Status.PREPARING: Color(1, 0.5, 0.1), Order.Status.EXECUTING: Color(1, 1, 1, 0.8)}
const AUTO := Order.AUTO

var main
var sim
var terrain
## The unit orders are being written for: a Brigade or a battalion (Formation).
var selected = null
var zoom := 1.0
var view_center := Vector2.ZERO  # world (x, z) at the centre of the screen
var _relief: ColorRect
var _panning := false
var _font: Font

# The order being written, not yet sent.
var _has_draft := false
var _draft_objective = null
var _draft_kind: int = Order.Kind.MOVE
var _draft_ftype: int = AUTO
var _draft_fire: int = AUTO
var _draft_skirm: int = AUTO
var _draft_intensity: int = Order.Intensity.PRESS
var _draft_dest := Vector2.ZERO
var _draft_facing := 0.0  # the front the unit would likely choose if it acted now
var _draft_shape: int = T.LINE

var _popup: PanelContainer
var _popup_title: Label
var _popup_front: Label
var _kind_buttons: Array = []
var _ftype_buttons: Array = []
var _fire_buttons: Array = []
var _skirm_buttons: Array = []
var _intensity_buttons: Array = []
var _intensity_row: Control
var _skirm_row: Control


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


## The order sheet: what to do, in what formation, how to fire, skirmishers,
## how hard to attack, the front the unit is likely to take, and Issue / Cancel.
## It sits beside the objective and follows it as the map moves.
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
	col.add_theme_constant_override("separation", 6)
	_popup.add_child(col)
	_popup_title = _popup_label(col, 15)
	_kind_buttons = _choice_row(col, "Order", Order.KIND_NAMES, func(i): _set_kind(i))[0]
	var ftypes := ["Auto"] + Array(Formation.TYPE_NAMES).slice(0, 4)
	for k in range(1, 5):
		ftypes[k] = "%d %s" % [k, ftypes[k]]
	_ftype_buttons = _choice_row(col, "Formation", ftypes, func(i): set_draft_ftype(i - 1))[0]
	_fire_buttons = _choice_row(col, "Fire", ["Auto"] + Array(Formation.FIRE_NAMES), func(i): _draft_fire = i - 1)[0]
	var sk := _choice_row(col, "Skirmishers", ["Auto", "Out", "In"], func(i): _draft_skirm = [AUTO, 1, 0][i])
	_skirm_buttons = sk[0]
	_skirm_row = sk[1]
	var it := _choice_row(col, "Attack", Order.INTENSITY_NAMES, func(i): _draft_intensity = i)
	_intensity_buttons = it[0]
	_intensity_row = it[1]
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


## A labelled row of toggle buttons, one pressed at a time. [buttons, row]
func _choice_row(parent: Control, title: String, names: Array, on_pick: Callable) -> Array:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _popup_label(row, 13)
	l.text = title
	l.custom_minimum_size.x = 92
	var group := ButtonGroup.new()
	var out := []
	for i in names.size():
		var btn := Button.new()
		btn.text = names[i]
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(on_pick.bind(i))
		row.add_child(btn)
		out.append(btn)
	return [out, row]


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

func select(unit) -> void:
	if unit != selected:
		cancel_draft()
	selected = unit


func _is_battalion(u) -> bool:
	return u != null and u.level == Command.Level.BATTALION


func has_draft() -> bool:
	return _has_draft


## Right-click: start an order for the selected unit, or move the objective of
## the one being written (keeping the rest of the sheet). An enemy unit under
## the cursor makes it an attack on that unit.
func _set_draft_target(screen: Vector2) -> void:
	var enemy = _pick_enemy(screen)
	if not _has_draft:
		_has_draft = true
		_set_kind(Order.Kind.MOVE)
		set_draft_ftype(AUTO)
		_draft_fire = AUTO
		_fire_buttons[0].button_pressed = true
		_draft_skirm = AUTO
		_skirm_buttons[0].button_pressed = true
		_draft_intensity = Order.Intensity.PRESS
		_intensity_buttons[_draft_intensity].button_pressed = true
	if enemy != null:
		_draft_objective = Objective.on_unit(enemy)
		_set_kind(Order.Kind.ATTACK)
	else:
		_draft_objective = Objective.point(to_world(screen))
	_popup.visible = true
	_update_draft()


func _set_kind(k: int) -> void:
	_draft_kind = k
	_kind_buttons[k].button_pressed = true


func set_draft_ftype(t: int) -> void:
	_draft_ftype = t
	_ftype_buttons[t + 1].button_pressed = true


func cancel_draft() -> void:
	_has_draft = false
	if _popup:
		_popup.visible = false


## Seal the order and hand it to a courier.
func issue_draft() -> void:
	if not _has_draft:
		return
	var o = sim.new_order(selected, _draft_kind, _draft_objective)
	o.ftype = _draft_ftype
	o.fire_mode = _draft_fire
	o.skirmishers = _draft_skirm
	o.intensity = _draft_intensity
	main.send_player_order(o)
	cancel_draft()


func _update_draft() -> void:
	var u = selected
	if u == null or u.is_gone():
		cancel_draft()
		return
	var bn := _is_battalion(u)
	# Only a detached battalion can be told to rejoin; skirmishers are battalion
	# business (a brigade passes the wish on to all its battalions).
	_kind_buttons[Order.Kind.REJOIN].visible = bn and u.detached
	if _draft_kind == Order.Kind.REJOIN and not _kind_buttons[Order.Kind.REJOIN].visible:
		_set_kind(Order.Kind.MOVE)
	_intensity_row.visible = _draft_kind == Order.Kind.ATTACK
	var attack_unit: bool = _draft_objective.kind == Objective.Kind.UNIT
	_draft_dest = _draft_objective.anchor()
	var from: Vector2 = u.position()
	# The formation and front the unit would most likely choose if it acted now.
	_draft_shape = _draft_ftype
	if _draft_shape < 0:
		if _draft_kind == Order.Kind.ATTACK:
			_draft_shape = Doctrine.of(u.army).attack_ftype
		else:
			_draft_shape = _prevailing_ftype(u)
	var front: String
	if _draft_kind == Order.Kind.ATTACK and attack_unit:
		var to: Vector2 = _draft_dest - from
		_draft_facing = Orientation.yaw_of(to)
		_draft_dest -= to.normalized() * 20.0
		front = "facing the enemy (%s)" % Orientation.compass(_draft_facing)
	else:
		var plan := Orientation.decide(sim, u, _draft_dest, _draft_shape)
		_draft_facing = plan.facing
		front = Orientation.describe(plan.facing, plan.reason)
	var dist := _distance_text(from.distance_to(_draft_dest))
	match _draft_kind:
		Order.Kind.ATTACK:
			_popup_title.text = "%s: attack %s (%s)" % [u.title, _draft_objective.unit.label if attack_unit else "this position", dist]
		Order.Kind.HOLD:
			_popup_title.text = "%s: hold this ground (%s)" % [u.title, dist]
		Order.Kind.REJOIN:
			_popup_title.text = "%s: rejoin %s" % [u.title, u.parent.label]
		_:
			_popup_title.text = "%s: march %s, then form" % [u.title, dist]
	_popup_front.text = "Front at the commander's discretion: likely %s" % front
	if bn and not u.detached and u.parent != null:
		_popup_front.text += "\nOrdering a battalion directly detaches it from %s." % u.parent.label
	# Beside the objective, flipped to the other side near the map's edges.
	_popup.reset_size()
	var s := _popup.size
	var anchor := to_px(_draft_dest)
	var p := anchor + Vector2(18, 18)
	if p.x + s.x > size.x - 8.0:
		p.x = anchor.x - 18.0 - s.x
	if p.y + s.y > size.y - 8.0:
		p.y = anchor.y - 18.0 - s.y
	_popup.position = p.clamp(Vector2(8, 60), (size - s - Vector2(8, 8)).max(Vector2(8, 60)))


## The formation most of the unit's battalions are in now (line for a march).
func _prevailing_ftype(u) -> int:
	var counts := [0, 0, 0, 0]
	for f in u.battalions_all():
		if not f.dead and f.ftype < counts.size():
			counts[f.ftype] += 1
	var t: int = counts.find(counts.max())
	return T.LINE if _is_battalion(u) and t == T.MARCH else t


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
		_draw_block(p, yaw, f.footprint_as(ft), col, ft == T.OPEN)
		if f == selected:
			_outline(_block_pts(p, yaw, f.footprint_as(ft)), SELECT, 2.0)
		if f.army == main.PLAYER_ARMY and f.detached:
			draw_circle(to_px(p) + Vector2(0, -6), 3.0, DETACHED)
		if labels:
			var text: String = f.label + (" (detached)" if f.detached and f.army == main.PLAYER_ARMY else "")
			draw_string(_font, to_px(p) + Vector2(4, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.darkened(0.4))

	for b in sim.brigades:
		if b.army != main.PLAYER_ARMY or b.alive().is_empty():
			continue
		var c := to_px(b.centroid())
		if b == selected:
			draw_arc(c, 22.0, 0, TAU, 32, SELECT, 2.0)
		draw_string(_font, c + Vector2(-20, -14 - (10 if labels else 0)), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)

	for o in main.player_orders:
		var st: int = o.status
		if not STATUS_COLOUR.has(st):
			continue
		# Until the recipient acts on it, the order has no front: only he decides that.
		var dest: Vector2 = o.dest()
		_draw_order(o.recipient.position(), dest, o.facing, STATUS_COLOUR[st], st == Order.Status.RIDING)
		var text: String = Order.KIND_NAMES[o.kind] if o.ftype < 0 or o.kind != Order.Kind.MOVE else Formation.TYPE_NAMES[o.ftype]
		if STATUS_TEXT[st] != "":
			text += ", " + STATUS_TEXT[st]
		draw_string(_font, to_px(dest) + Vector2(10, 16), "%s: %s" % [o.recipient.label, text], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)

	for c in sim.couriers:
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
	var help := "MAP  |  %s  |  wheel zoom, drag pan  |  LMB brigade (again: battalion)  |  RMB where to go, or an enemy to attack  |  Enter issue, Esc cancel" % main.clock_text()
	draw_string(_font, Vector2(16, 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PARCHMENT)
	var sel := "Selected: %s" % (_selection_text() if selected != null else "none (left-click a brigade)")
	draw_string(_font, Vector2(16, 44), sel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PARCHMENT)


func _selection_text() -> String:
	if not _is_battalion(selected):
		return selected.title
	var f = selected
	var s := "%s (%s), %s, %s" % [f.title, f.parent.label, f.TYPE_NAMES[f.ftype].to_lower(), f.MORALE_NAMES[f.morale_state]]
	if f.engaged:
		s += ", firing" if f.firing or sim.time - f.last_shot < 25.0 else ", engaged"
	if f.detached:
		s += ", detached"
	return s


## The order being written: the route, and a ghost of the unit as it would stand
## at the objective in the chosen formation, on the front it would likely choose.
func _draw_draft() -> void:
	var u = selected
	var bns: Array = []
	for f in u.battalions_all():
		if not f.dead and (not f.detached or u == f):
			bns.append(f)
	var slots: Array = [_draft_dest] if bns.size() == 1 else sim.assign_slots(bns, _draft_dest, _draft_facing, _draft_shape)
	for k in bns.size():
		_outline(_block_pts(slots[k], _draft_facing, bns[k].footprint_as(_draft_shape)), DRAFT, 1.5)
	draw_line(to_px(u.position()), to_px(_draft_dest), DRAFT, 2.0)
	if _draft_objective.kind == Objective.Kind.UNIT:
		draw_arc(to_px(_draft_objective.anchor()), 12.0, 0, TAU, 24, Color(1, 0.3, 0.2), 2.5)
	else:
		draw_circle(to_px(_draft_dest), 4.0, DRAFT)


func _outline(pts: PackedVector2Array, col: Color, width: float) -> void:
	pts.append(pts[0])
	draw_polyline(pts, col, width)


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


## A battalion's block; skirmishers in open order as a dotted line.
func _draw_block(p: Vector2, yaw: float, fp: Vector2, col: Color, open := false) -> void:
	var pts := _block_pts(p, yaw, fp)
	if open:
		draw_dashed_line(pts[0], pts[1], col, 2.0, 3.0)
		return
	draw_colored_polygon(pts, col)
	draw_line(pts[0], pts[1], col.darkened(0.5), 1.5)


## Route and destination. `facing` is null until the unit has chosen its
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
					var f = _pick_own(mb.position)
					if f != null:
						_select_from_click(f)
					else:
						_panning = true
				else:
					_panning = false
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and selected != null:
					_set_draft_target(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			view_center -= mm.relative / px_per_m()
			_clamp_view()
		accept_event()


## A click on a battalion selects its brigade; a second click (or a click when
## zoomed in, or on a detached battalion) selects the battalion itself.
func _select_from_click(f) -> void:
	var b = sim.brigades[f.brigade]
	var same_brigade: bool = selected == b or (_is_battalion(selected) and selected.brigade == f.brigade)
	if zoom >= BATTALION_ZOOM or same_brigade or f.detached:
		select(f)
	else:
		select(b)


## Own battalion nearest the cursor (within 16 px).
func _pick_own(p: Vector2):
	var best = null
	var bd := 16.0
	for f in sim.formations:
		if f.dead or f.army != main.PLAYER_ARMY:
			continue
		var d := to_px(f.cpos).distance_to(p)
		if d < bd:
			bd = d
			best = f.parent if f.is_skirmisher else f  # orders go to their battalion
	return best


## Enemy battalion drawn under the cursor (where it was last seen).
func _pick_enemy(p: Vector2):
	var best = null
	var bd := 14.0
	for f in sim.formations:
		if f.dead or f.army == main.PLAYER_ARMY or sim.time - f.seen_time > 1800.0:
			continue
		var d := to_px(f.seen_pos).distance_to(p)
		if d < bd:
			bd = d
			best = f
	return best
