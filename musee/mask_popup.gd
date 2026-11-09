extends Control
## Fiche du masque volé : le masque flotte et tourne dans un cadre, avec son
## nom et son histoire. Met le jeu en pause jusqu'à « Continuer ».
## Les masques et leurs histoires sont inventés pour le jeu.


var _pivot := Node3D.new()
var _title := Label.new()
var _material := Label.new()
var _story := Label.new()
var _button := Button.new()
var _t := 0.0
var _note := Label.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # fonctionne pendant la pause
	set_anchors_preset(PRESET_FULL_RECT)
	hide()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.06, 0.05, 0.92)
	box.border_color = Color(0.85, 0.65, 0.3)
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	# Le masque en 3D dans son propre petit monde.
	var view_box := SubViewportContainer.new()
	view_box.stretch = true
	view_box.custom_minimum_size = Vector2(220, 260)
	row.add_child(view_box)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view_box.add_child(view)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 0.95)
	cam.fov = 40
	view.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 25, 0)
	view.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.5, 0.3, 0.6)
	fill.light_energy = 0.6
	view.add_child(fill)
	view.add_child(_pivot)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	_title.add_theme_font_override("font", preload("res://musee/fonts/Cinzel.ttf"))
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_material.add_theme_font_size_override("font_size", 14)
	_material.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.add_theme_font_size_override("font_size", 17)
	var note := _note
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_button.text = "Continuer à jouer"
	_button.custom_minimum_size = Vector2(0, 48)
	_button.add_theme_font_size_override("font_size", 20)
	_button.pressed.connect(_close)
	for c in [_title, _material, _story, note, _button]:
		col.add_child(c)


func show_mask(vitrine: Node3D) -> void:
	var info: Array = Levels.MASKS.get(vitrine.mask_id, ["Masque inconnu", "", ""])
	_title.text = info[0]
	_material.text = info[1]
	_story.text = info[2]
	_note.text = info[5] if info.size() > 5 else ""
	_note.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if "DOCUMENTÉ" in _note.text else Color(0.7, 0.7, 0.7))
	for c in _pivot.get_children():
		c.queue_free()
	var copy: Node3D = vitrine.get_node("Mask").duplicate()
	copy.transform = Transform3D.IDENTITY
	copy.show()
	_pivot.add_child(copy)
	_t = 0.0
	position = Vector2.ZERO
	size = get_viewport_rect().size # plein écran (le parent est un CanvasLayer)
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_button.grab_focus()


func _close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = false
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_pivot.rotation.y = sin(_t * 0.9) * 0.8 # oscille pour montrer le relief
	_pivot.position.y = sin(_t * 2.0) * 0.03 # flotte doucement


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Sur mobile, la conversion toucher -> souris est désactivée : on gère le doigt ici.
	if event is InputEventScreenTouch and event.pressed and _button.get_global_rect().has_point(event.position):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_close()
		get_viewport().set_input_as_handled()
