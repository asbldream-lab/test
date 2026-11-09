extends Control
## Manette tactile transparente : joystick, boutons Courir / S'accroupir / Rejouer,
## et glisser sur l'écran pour tourner la caméra. Multi-touch géré à la main.

const JOY_RADIUS := 110.0
const KNOB_RADIUS := 45.0
const LOOK_SPEED := 1.5

var player: MuseumPlayer

var _u := 1.0 # échelle selon la taille de l'écran
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_finger := -1
var _look_finger := -1
var _look_last := Vector2.ZERO
var _look_pending := Vector2.ZERO
var _run_finger := -1
var _crouch_on := false
var _buttons := {}
var _font: Font
var _box := StyleBoxFlat.new()
var _box_on := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	for b in [_box, _box_on]:
		b.set_corner_radius_all(18)
		b.set_border_width_all(3)
		b.border_color = Color(1, 1, 1, 0.6)
	_box.bg_color = Color(1, 1, 1, 0.12)
	_box_on.bg_color = Color(1, 1, 1, 0.38)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "run", "crouch"]:
		Input.action_release(a)


func _layout() -> void:
	var s := get_viewport_rect().size
	_u = clampf(s.y / 720.0, 0.6, 1.6)
	var m := 36.0 * _u
	_joy_center = Vector2(m + (JOY_RADIUS + 10) * _u, s.y - m - (JOY_RADIUS + 30) * _u)
	var bw := 230.0 * _u
	var bh := 90.0 * _u
	_buttons = {
		"run": Rect2(s.x - m - bw, s.y - m - bh * 2 - 24 * _u, bw, bh),
		"crouch": Rect2(s.x - m - bw, s.y - m - bh, bw, bh),
		"restart": Rect2(s.x - m - 190 * _u, m, 190 * _u, 64 * _u),
	}
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		var i: int = event.index
		if event.pressed:
			if _buttons.run.has_point(p):
				_run_finger = i
				Input.action_press("run")
			elif _buttons.crouch.has_point(p):
				_crouch_on = not _crouch_on
				if _crouch_on:
					Input.action_press("crouch")
				else:
					Input.action_release("crouch")
			elif _buttons.restart.has_point(p):
				get_tree().reload_current_scene()
			elif _joy_finger == -1 and p.x < get_viewport_rect().size.x * 0.45 and p.y > get_viewport_rect().size.y * 0.35:
				_joy_finger = i
				_update_joy(p)
			elif _look_finger == -1:
				_look_finger = i
				_look_last = p
		else:
			if i == _joy_finger:
				_joy_finger = -1
				_set_joy(Vector2.ZERO)
			elif i == _run_finger:
				_run_finger = -1
				Input.action_release("run")
			elif i == _look_finger:
				_look_finger = -1
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			_update_joy(event.position)
		elif event.index == _look_finger:
			# Delta calculé nous-mêmes par doigt : event.relative est peu fiable
			# en multi-touch sur navigateur (sauts quand deux doigts bougent).
			var d: Vector2 = event.position - _look_last
			_look_last = event.position
			if d.length() < 150.0 * _u:
				_look_pending += Vector2(d.x, d.y * 0.6) * LOOK_SPEED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Lissage : on applique une partie du mouvement en attente à chaque image.
	if player == null or _look_pending.length() < 0.01:
		return
	var step := _look_pending * minf(1.0, 18.0 * delta)
	_look_pending -= step
	player.rotate_camera(step)


func _update_joy(p: Vector2) -> void:
	_set_joy(((p - _joy_center) / (JOY_RADIUS * _u)).limit_length(1.0))


func _set_joy(v: Vector2) -> void:
	_joy_vec = v
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)
	queue_redraw()


func _axis(neg: String, pos: String, value: float) -> void:
	if value < -0.15:
		Input.action_press(neg, -value)
	else:
		Input.action_release(neg)
	if value > 0.15:
		Input.action_press(pos, value)
	else:
		Input.action_release(pos)


func _draw() -> void:
	var s := get_viewport_rect().size
	# Joystick
	draw_circle(_joy_center, JOY_RADIUS * _u, Color(1, 1, 1, 0.1))
	draw_arc(_joy_center, JOY_RADIUS * _u, 0, TAU, 48, Color(1, 1, 1, 0.5), 3)
	var knob_alpha := 0.45 if _joy_finger != -1 else 0.28
	draw_circle(_joy_center + _joy_vec * JOY_RADIUS * _u, KNOB_RADIUS * _u, Color(1, 1, 1, knob_alpha))
	_text("SE DÉPLACER", _joy_center + Vector2(0, (JOY_RADIUS + 26) * _u), 20)
	# Boutons
	_button("run", "COURIR", "(maintenir - bruyant !)", _run_finger != -1)
	_button("crouch", "S'ACCROUPIR", "(activé)" if _crouch_on else "(appuie : on / off)", _crouch_on)
	_button("restart", "REJOUER", "", false)
	# Aide
	_text("Objectif : atteins la porte verte sans être vu", Vector2(s.x * 0.42, 50 * _u), 22)
	_text("Glisse le doigt ici pour tourner la caméra", Vector2(s.x * 0.5, s.y * 0.3), 18, 0.45)
	# Téléphone à la verticale
	if s.y > s.x:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.85))
		_text("Tourne ton téléphone", s / 2 - Vector2(0, 30 * _u), 40)
		_text("à l'horizontale pour jouer", s / 2 + Vector2(0, 30 * _u), 40)


func _button(id: String, title: String, sub: String, active: bool) -> void:
	var r: Rect2 = _buttons[id]
	draw_style_box(_box_on if active else _box, r)
	var c := r.get_center()
	if sub.is_empty():
		_text(title, c, 26)
	else:
		_text(title, c - Vector2(0, 13 * _u), 26)
		_text(sub, c + Vector2(0, 22 * _u), 15, 0.75)


func _text(t: String, center: Vector2, font_size: int, alpha := 0.95) -> void:
	var fs := int(font_size * _u)
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := center + Vector2(-w / 2.0, fs * 0.35)
	draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5 * _u), Color(0, 0, 0, alpha * 0.7))
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
