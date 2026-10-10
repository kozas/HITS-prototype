extends Control
## Order of battle (O): the chain of command as a collapsible tree,
## Army > Corps > Division > Brigade > Battalion, with commanders, strength and
## what each unit is doing. Your own army is shown in full (M1: as of the last
## returns). The enemy only as far as he has been seen, with strengths guessed.
## Double-click a unit to find it on the map.

const Formation = preload("res://src/formation.gd")
const Command = preload("res://src/command.gd")
const Brigade = preload("res://src/brigade.gd")
const Order = preload("res://src/order.gd")

const PARCHMENT := Color(0.93, 0.88, 0.74)
const DIM := Color(0.68, 0.64, 0.54)
const ENGAGED := Color(1.0, 0.65, 0.3)
const ROUTING := Color(1.0, 0.35, 0.3)
## Map zoom when jumping to a unit, by level: army, corps, division, brigade, battalion.
const FOCUS_ZOOM := [1.0, 2.0, 3.0, 5.0, 9.0]

var battle
var sim
var tree: Tree
var _rows: Array = []      # [TreeItem, Command or Formation, is_enemy]
var _collapsed := {}       # instance id -> collapsed, kept across rebuilds
var _refresh_t := 0.0


func setup(b) -> void:
	battle = b
	sim = b.sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.08, 0.065, 0.97)
	style.border_color = Color(0.4, 0.34, 0.24)
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Order of Battle"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", PARCHMENT)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Double-click a unit to find it on the map.   O or Esc to close."
	hint.add_theme_color_override("font_color", DIM)
	col.add_child(hint)

	tree = Tree.new()
	tree.columns = 4
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in 4:
		tree.set_column_title(c, ["Unit", "Commander", "Strength", "Situation"][c])
		tree.set_column_expand_ratio(c, [5, 4, 2, 4][c])
		tree.set_column_clip_content(c, true)
	var tree_bg := StyleBoxFlat.new()
	tree_bg.bg_color = Color(0.11, 0.1, 0.08)
	tree.add_theme_stylebox_override("panel", tree_bg)
	tree.add_theme_color_override("font_color", PARCHMENT)
	tree.item_activated.connect(_on_activated)
	col.add_child(tree)


func open() -> void:
	visible = true
	_build()
	tree.grab_focus()


func close() -> void:
	_remember_collapsed()
	visible = false


func _process(dt: float) -> void:
	if not visible:
		return
	_refresh_t -= dt
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_refresh()


func _build() -> void:
	_remember_collapsed()
	tree.clear()
	_rows.clear()
	var root := tree.create_item()
	for a in sim.armies:
		_add(root, a, a.army != battle.PLAYER_ARMY)
	_refresh()


func _remember_collapsed() -> void:
	for r in _rows:
		_collapsed[r[1].get_instance_id()] = r[0].collapsed


## Adds `node` (a Command or a battalion) and everything under it.
func _add(parent: TreeItem, node, enemy: bool) -> void:
	if enemy and not _known(node):
		return
	var it := tree.create_item(parent)
	it.set_text(0, node.title)
	it.set_text(1, node.commander)
	it.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
	it.set_metadata(0, node)
	_rows.append([it, node, enemy])
	if node is Formation:
		it.set_custom_color(0, DIM)
		return
	# Armies and corps open, divisions and brigades folded, unless changed.
	it.collapsed = _collapsed.get(node.get_instance_id(), node.level >= Command.Level.DIVISION)
	if node is Brigade:
		for f in node.battalions:
			_add(it, f, enemy)
	else:
		for s in node.subordinates:
			_add(it, s, enemy)


## The enemy: only what has been seen.
func _known(node) -> bool:
	if node is Formation:
		return node.seen_time > -1.0e8
	for f in node.battalions_all():
		if f.seen_time > -1.0e8:
			return true
	return false


func _refresh() -> void:
	for r in _rows:
		var it: TreeItem = r[0]
		var node = r[1]
		var enemy: bool = r[2]
		var bns: Array = [node] if node is Formation else node.battalions_all()
		var men := 0
		var engaged := 0
		var routing := 0
		var seen := INF
		for f in bns:
			if enemy and f.seen_time < -1.0e8:
				continue
			if not f.dead:
				men += f.strength
			engaged += 1 if f.engaged and not f.dead else 0
			routing += 1 if f.routing and not f.dead else 0
			seen = minf(seen, sim.time - f.seen_time)
		if enemy:
			# Seen, not counted: a guess to the nearest hundred.
			it.set_text(2, "~%s" % _thousands(int(round(men / 100.0)) * 100))
		else:
			it.set_text(2, _thousands(men))
		var text := ""
		if node is Formation:
			text = _battalion_state(node)
		elif node is Brigade and not enemy:
			text = _brigade_state(node)
		elif engaged > 0 or routing > 0:
			text = "%d engaged, %d routing" % [engaged, routing]
		if enemy:
			text = ("seen %d min ago" % int(seen / 60.0)) if seen > 90.0 else ("in sight" + ("" if text == "" else ": " + text))
		it.set_text(3, text)
		var col := PARCHMENT
		if routing > 0 and (node is Formation or routing * 2 >= bns.size()):
			col = ROUTING
		elif engaged > 0:
			col = ENGAGED
		it.set_custom_color(3, col)


func _battalion_state(f) -> String:
	if f.dead:
		return "dispersed"
	if f.routing:
		return "ROUTING"
	var s: String = Formation.TYPE_NAMES[f.ftype]
	if f.is_transitioning(sim.time):
		s = "forming " + s.to_lower()
	elif f.engaged:
		s += ", engaged"
	elif f.moving:
		s += ", marching"
	return s


func _brigade_state(b) -> String:
	if b.alive().is_empty():
		return "destroyed"
	if b.awaiting:
		return "courier on the way"
	if not b.inbox.is_empty():
		return "orders received"
	if b.order != null and b.order.status == Order.Status.EXECUTING:
		return "carrying out orders"
	return "holding"


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _on_activated() -> void:
	var it := tree.get_selected()
	if it == null:
		return
	var node = it.get_metadata(0)
	var enemy: bool = node.army != battle.PLAYER_ARMY
	var bns: Array = [node] if node is Formation else node.battalions_all()
	var c := Vector2.ZERO
	var n := 0
	for f in bns:
		if f.dead or (enemy and f.seen_time < -1.0e8):
			continue
		c += f.seen_pos if enemy else f.cpos
		n += 1
	if n == 0:
		return
	var level: int = 4 if node is Formation else node.level
	var brigade_id: int = -1
	if not enemy:
		brigade_id = node.brigade if node is Formation else (node.id if node is Brigade else -1)
	battle.show_on_map(c / n, FOCUS_ZOOM[level], brigade_id)
