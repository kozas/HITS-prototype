extends Control
## Main menu: pick a scenario. Command-line shortcuts skip the menu:
##   -- --bench               scripted benchmark run
##   -- --scenario=contact    straight into Brigade contact
##   -- --scenario=benchmark  straight into the full battle

const GS = preload("res://src/game_state.gd")

const PARCHMENT := Color(0.93, 0.88, 0.74)
const DIM := Color(0.68, 0.64, 0.54)

const ITEMS := [
	["Brigade contact", "A French brigade advances in line on an Allied brigade.\nMusketry range in about 30 seconds.", GS.Scenario.BRIGADE_CONTACT],
	["Benchmark", "The full 1:1 stress test: 192,000 men in 320 battalions\non a 6 km field, with couriers and the map.", GS.Scenario.BENCHMARK],
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for a in OS.get_cmdline_user_args():
		if a == "--bench" or a == "--scenario=benchmark":
			GameState.start.call_deferred(GameState.Scenario.BENCHMARK)
			return
		if a == "--scenario=contact":
			GameState.start.call_deferred(GameState.Scenario.BRIGADE_CONTACT)
			return
	_build()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(a.get_slice("=", 1).path_join("menu.png"))
			get_tree().quit()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.085, 0.08, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)

	col.add_child(_label("Headquarters in the Saddle", 50, PARCHMENT))
	col.add_child(_label("Prototype M0  ·  command by courier", 18, DIM))
	col.add_child(_spacer(36))

	var first: Button = null
	for item in ITEMS:
		var b := _button(item[0])
		b.pressed.connect(GameState.start.bind(item[2]))
		col.add_child(b)
		col.add_child(_label(item[1], 14, DIM))
		col.add_child(_spacer(18))
		if first == null:
			first = b
	var quit := _button("Quit")
	quit.pressed.connect(get_tree().quit)
	col.add_child(quit)
	col.add_child(_spacer(30))
	col.add_child(_label("In battle: Esc for the menu, M for the map, H for help.", 13, DIM))
	first.grab_focus()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.84))
	b.add_theme_color_override("font_focus_color", Color(1, 0.96, 0.84))
	b.add_theme_stylebox_override("normal", _box(Color(0.16, 0.13, 0.09), Color(0.4, 0.34, 0.24)))
	b.add_theme_stylebox_override("hover", _box(Color(0.24, 0.19, 0.12), PARCHMENT))
	b.add_theme_stylebox_override("focus", _box(Color(0.24, 0.19, 0.12), PARCHMENT))
	b.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.24, 0.15), PARCHMENT))
	return b


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s
