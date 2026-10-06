extends Control
## Stats overlay, battle clock, dispatch messages and key help.

const HELP := """[W] trot  [Shift+W] gallop  [Ctrl+W] walk  [S] back  [A/D] sidestep  mouse: look
[M]/[Tab] map & orders    [F] free camera (QE up/down, Shift fast)
[=]/[-] time scale   [P] pause   [G] AI autopilot for your army
[L] LOD mode   [O] LOS culling   [K] chaos: everyone changes formation
[H] hide help   [Esc] release mouse"""

var stats: Label
var clock: Label
var help: Label
var toasts: VBoxContainer


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats = _label(14)
	stats.position = Vector2(12, 8)
	clock = _label(22)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin(clock, Vector4(1, 0, 1, 0), Vector4(-420, 8, -12, 70))
	help = _label(13)
	help.text = HELP
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pin(help, Vector4(1, 1, 1, 1), Vector4(-12, -12, -12, -12))
	toasts = VBoxContainer.new()
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(toasts, Vector4(0, 1, 0, 1), Vector4(12, -12, 700, -12))
	add_child(toasts)


## anchors / offsets as (left, top, right, bottom)
func _pin(c: Control, a: Vector4, o: Vector4) -> void:
	c.anchor_left = a.x
	c.anchor_top = a.y
	c.anchor_right = a.z
	c.anchor_bottom = a.w
	c.offset_left = o.x
	c.offset_top = o.y
	c.offset_right = o.z
	c.offset_bottom = o.w


func _label(sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	toasts.add_child(l)
	if toasts.get_child_count() > 6:
		toasts.get_child(0).queue_free()
	get_tree().create_timer(9.0).timeout.connect(l.queue_free)
