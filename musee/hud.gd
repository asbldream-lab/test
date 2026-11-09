extends Control
## Interface du jeu : cartouche du niveau + masques, jauge de visibilité (œil),
## aide clavier discrète, message central et vignettage de l'image.

const TITLE_FONT := preload("res://musee/fonts/Cinzel.ttf")
const GOLD := Color(0.86, 0.7, 0.38)

var _level := Label.new()
var _masks := Label.new()
var _meter := Control.new()
var _state := Label.new()
var _help := Label.new()
var _vis := 0.0 # valeur affichée (lissée)
var _target := 0.0
var _seen := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)

	# Vignettage + légère teinte chaude (donne de la profondeur à l'image).
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.mouse_filter = MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(0.03, 0.015, 0.0, v * 0.75);
}"""
	vignette.material = ShaderMaterial.new()
	vignette.material.shader = sh
	add_child(vignette)

	# Cartouche en haut à gauche.
	var card := _panel()
	card.position = Vector2(16, 14)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	_level.add_theme_font_override("font", TITLE_FONT)
	_level.add_theme_font_size_override("font_size", 20)
	_level.add_theme_color_override("font_color", GOLD)
	_masks.add_theme_font_size_override("font_size", 16)
	_masks.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	col.add_child(_level)
	col.add_child(_masks)
	add_child(card)

	# Jauge de visibilité en haut au centre.
	_meter.custom_minimum_size = Vector2(300, 46)
	_meter.size = _meter.custom_minimum_size
	_meter.mouse_filter = MOUSE_FILTER_IGNORE
	_meter.draw.connect(_draw_meter)
	add_child(_meter)
	_state.add_theme_font_override("font", TITLE_FONT)
	_state.add_theme_font_size_override("font_size", 13)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter.add_child(_state)
	_state.position = Vector2(40, 26)
	_state.size = Vector2(250, 18)

	# Aide clavier en bas à gauche.
	var hp := _panel(0.45)
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.position = Vector2(16, -16)
	hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	_help.text = "ZQSD  marcher    MAJ  courir    C  s'accroupir / glissade\nESPACE  roulade    E  prendre    R  recommencer    ÉCHAP  souris"
	hp.add_child(_help)
	add_child(hp)
	hp.name = "Help"


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_meter.position = Vector2(size.x / 2 - 150, 14)


func _panel(alpha := 0.6) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, alpha)
	sb.border_color = Color(GOLD, 0.6)
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 14
	p.add_theme_stylebox_override("panel", sb)
	return p


func setup(level_index: int, level_count: int, level_name: String, touch: bool) -> void:
	_level.text = "Salle %d / %d  ·  %s" % [level_index + 1, level_count, level_name]
	if touch:
		get_node("Help").hide()


func set_masks(taken: int, total: int) -> void:
	_masks.text = "◆  Masques récupérés : %d / %d" % [taken, total]


## v : 0 = invisible, 1 = repéré ; seen : un gardien te voit en ce moment.
func set_visibility(v: float, seen: bool) -> void:
	_target = clampf(v, 0.0, 1.0)
	if seen:
		_target = maxf(_target, 0.12)
	_seen = seen


func _process(delta: float) -> void:
	_vis = move_toward(_vis, _target, delta * 2.5)
	if _vis > 0.66:
		_state.text = "REPÉRÉ IMMINENT"
	elif _vis > 0.25 or _seen:
		_state.text = "SUSPECT"
	elif _vis > 0.02:
		_state.text = "MÉFIANCE"
	else:
		_state.text = "INVISIBLE"
	_state.add_theme_color_override("font_color", _color(_vis))
	_meter.queue_redraw()


func _color(v: float) -> Color:
	var calm := Color(0.45, 0.85, 0.75)
	var warn := Color(1.0, 0.75, 0.25)
	var alarm := Color(1.0, 0.22, 0.18)
	return calm.lerp(warn, clampf(v * 2.0, 0, 1)).lerp(alarm, clampf(v * 2.0 - 1.0, 0, 1))


func _draw_meter() -> void:
	var c := _color(_vis)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.03, 0.02, 0.6)
	bg.set_corner_radius_all(6)
	_meter.draw_style_box(bg, Rect2(Vector2.ZERO, _meter.size))
	# Œil : ouvert selon la visibilité.
	var center := Vector2(22, 23)
	var open := lerpf(0.25, 1.0, _vis)
	var pts := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0 * TAU
		pts.append(center + Vector2(cos(t) * 14.0, sin(t) * 8.0 * open))
	_meter.draw_colored_polygon(pts, Color(c, 0.25))
	_meter.draw_polyline(pts, c, 2.0, true)
	_meter.draw_circle(center, 4.0 * open + 1.0, c)
	# Barre.
	var bar := Rect2(44, 10, 244, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(6)
	_meter.draw_style_box(sb, bar)
	if _vis > 0.005:
		var fill := StyleBoxFlat.new()
		fill.bg_color = c
		fill.set_corner_radius_all(6)
		_meter.draw_style_box(fill, Rect2(bar.position, Vector2(maxf(12.0, bar.size.x * _vis), bar.size.y)))
