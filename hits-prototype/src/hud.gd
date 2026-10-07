extends Control
## Stats overlay, battle clock, dispatch messages and key help.

const HELP := """[W] trot  [Shift+W] gallop  [Ctrl+W] walk  [S] back  [A/D] sidestep  mouse: look
[M]/[Tab] map & orders    [F] free camera (QE up/down, Shift fast)
[=]/[-] time scale   [P] pause   [G] AI autopilot for your army
[L] LOD mode   [O] LOS culling   [K] chaos: everyone changes formation
[H] hide help   [Esc] menu"""

var stats: Label
var clock: Label
var help: Label
var toasts: VBoxContainer
var pause_panel: PanelContainer
var resume_button: Button


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


## Esc menu: Resume / Main menu, centred, hidden until opened.
func build_pause_menu(on_resume: Callable, on_menu: Callable) -> void:
	pause_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.08, 0.065, 0.94)
	style.border_color = Color(0.4, 0.34, 0.24)
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	pause_panel.add_theme_stylebox_override("panel", style)
	_pin(pause_panel, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-170, -95, 170, 95))
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pause_panel.add_child(col)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	col.add_child(title)
	resume_button = Button.new()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size = Vector2(290, 44)
	resume_button.pressed.connect(on_resume)
	col.add_child(resume_button)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(290, 44)
	menu.pressed.connect(on_menu)
	col.add_child(menu)
	pause_panel.visible = false
	add_child(pause_panel)


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
