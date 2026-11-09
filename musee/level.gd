extends Node3D
## Construit le niveau courant à partir de levels.gd : pièce, cloisons, colonnes,
## vitrines, gardiens, portes. Gère victoire, échec et passage au niveau suivant.

const VITRINE := preload("res://musee/vitrine.tscn")
const GUARD := preload("res://musee/guard.tscn")
const WALL_H := 4.0

static var current := 0 ## Niveau en cours (conservé quand la scène est rechargée).

@onready var player: MuseumPlayer = $Player
@onready var message: Label = $HUD/Message

var guards: Array[MuseumGuard] = []
var _data: Dictionary
var _over := false
var _won := false
var _touch := DisplayServer.is_touchscreen_available()
var _counter := Label.new()
var _popup: Control = preload("res://musee/mask_popup.gd").new()
var _pad: Control
var _flash := 0.0
var _exit_mat := StandardMaterial3D.new()


func _enter_tree() -> void:
	# Touches physiques : W/A/S/D = Z/Q/S/D sur clavier AZERTY.
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
		"crouch": [KEY_C], # pas Ctrl : sur Mac, Ctrl+flèches change de bureau
		"restart": [KEY_R],
		"interact": [KEY_E],
		"roll": [KEY_SPACE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _ready() -> void:
	# Relâche les actions restées "enfoncées" (ex. touche avalée par le système avant la mort).
	for a in InputMap.get_actions():
		Input.action_release(a)
	_data = Levels.LEVELS[current]
	_build()
	player.mask_taken.connect(_on_mask_taken)

	$HUD/Aide.text = "ZQSD : marcher   Maj : courir (bruyant)   C : s'accroupir   C en courant : glissade\n" \
		+ "Espace : roulade   E : prendre un masque   R : recommencer   Échap : libérer la souris\n" \
		+ "Objectif : vole les %d masques puis sors par la porte, sans te faire voir." % _total_masks()
	_counter.position = Vector2(16, 100) if not _touch else Vector2(16, 12)
	_counter.add_theme_font_size_override("font_size", 24)
	_counter.add_theme_constant_override("outline_size", 8)
	_counter.add_theme_color_override("font_outline_color", Color.BLACK)
	$HUD.add_child(_counter)
	_on_mask_taken(0)
	if _touch:
		_pad = preload("res://musee/touch_controls.gd").new()
		_pad.player = player
		$HUD.add_child(_pad)
		$HUD/Aide.hide()
	$HUD.add_child(_popup) # au-dessus de la manette
	_show("Niveau %d / %d\n%s" % [current + 1, Levels.LEVELS.size(), _data.name], Color(1, 0.9, 0.6), 3.0)


# --- Construction du niveau -------------------------------------------------

func _build() -> void:
	var w: float = _data.size.x
	var d: float = _data.size.y
	var floor_mat := _mat(Color(0.42, 0.28, 0.18), 0.5)
	var wall_mat := _mat(Color(0.55, 0.2, 0.17), 0.9)
	var col_mat := _mat(Color(0.78, 0.72, 0.62), 0.8)
	_exit_mat.emission_enabled = true

	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_mat)
	# Murs extérieurs puis cloisons intérieures.
	_box(Vector3(0, WALL_H / 2, -d / 2 - 0.2), Vector3(w + 0.8, WALL_H, 0.4), wall_mat)
	_box(Vector3(0, WALL_H / 2, d / 2 + 0.2), Vector3(w + 0.8, WALL_H, 0.4), wall_mat)
	_box(Vector3(-w / 2 - 0.2, WALL_H / 2, 0), Vector3(0.4, WALL_H, d), wall_mat)
	_box(Vector3(w / 2 + 0.2, WALL_H / 2, 0), Vector3(0.4, WALL_H, d), wall_mat)
	for r in _data.walls:
		_box(Vector3(r[0], WALL_H / 2, r[1]), Vector3(r[2], WALL_H, r[3]), wall_mat)
	for c in _data.columns:
		_column(Vector3(c[0], 0, c[1]), col_mat)

	_door(_data.entry, _mat(Color(0.3, 0.18, 0.1), 0.8))
	_door(_data.exit, _exit_mat)
	_exit_area(_data.exit)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 30, 0)
	sun.light_color = Color(1, 0.92, 0.8)
	sun.light_energy = 0.35
	add_child(sun)

	for v in _data.vitrines:
		var m: Array = Levels.MASKS[v[3]]
		var vit := VITRINE.instantiate()
		vit.mask_id = v[3]
		vit.face_color = m[3]
		vit.accent_color = m[4]
		vit.position = Vector3(v[0], 0, v[1])
		vit.rotation.y = deg_to_rad(v[2])
		add_child(vit)

	for g in _data.guards:
		var guard: MuseumGuard = GUARD.instantiate()
		var pts: Array[Vector3] = []
		for p in g.wp:
			pts.append(Vector3(p[0], 0, p[1]))
		guard.waypoints = pts
		guard.start_index = g.get("start", 0)
		guard.spin_speed = g.get("spin", 0.0)
		guard.position = pts[guard.start_index]
		add_child(guard)
		guard.player_spotted.connect(_on_spotted)
		guards.append(guard)

	player.global_position = Vector3(_data.spawn[0], 0, _data.spawn[1])
	player.set_facing(deg_to_rad(_data.spawn[2]))


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.material_override = mat
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = size
	body.add_child(mesh)
	body.add_child(col)
	add_child(body)


func _column(pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, WALL_H / 2, 0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	mesh.mesh.top_radius = 0.4
	mesh.mesh.bottom_radius = 0.45
	mesh.mesh.height = WALL_H
	mesh.material_override = mat
	var col := CollisionShape3D.new()
	col.shape = CylinderShape3D.new()
	col.shape.radius = 0.45
	col.shape.height = WALL_H
	body.add_child(mesh)
	body.add_child(col)
	add_child(body)


## Vecteur vers l'intérieur de la pièce pour un mur donné.
func _inward(side: String) -> Vector3:
	return {"N": Vector3(0, 0, 1), "S": Vector3(0, 0, -1), "E": Vector3(-1, 0, 0), "W": Vector3(1, 0, 0)}[side]


func _door(info: Array, mat: Material) -> void:
	var side: String = info[2]
	var horiz := side == "N" or side == "S"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(1.6, 2.4, 0.1) if horiz else Vector3(0.1, 2.4, 1.6)
	mesh.material_override = mat
	mesh.position = Vector3(info[0], 1.2, info[1]) + _inward(side) * 0.03
	add_child(mesh)


func _exit_area(info: Array) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector3(info[0], 1.25, info[1]) + _inward(info[2]) * 0.8
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1.6, 2.5, 1.6)
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_exit)


# --- Déroulement de la partie ----------------------------------------------

func _total_masks() -> int:
	return _data.vitrines.size()


func _on_mask_taken(total: int, vitrine: Node3D = null) -> void:
	_counter.text = "Masques : %d / %d" % [total, _total_masks()]
	if vitrine:
		# Laisse finir le geste de prise avant d'afficher la fiche du masque.
		get_tree().create_timer(0.8).timeout.connect(_popup.show_mask.bind(vitrine))
	# Porte rouge tant qu'il manque des masques, verte ensuite.
	var open := total >= _total_masks()
	_exit_mat.albedo_color = Color(0.2, 0.8, 0.3) if open else Color(0.8, 0.15, 0.1)
	_exit_mat.emission = Color(0.1, 0.9, 0.3) if open else Color(0.9, 0.1, 0.05)


func _show(text: String, color: Color, seconds := 0.0) -> void:
	message.text = text
	message.modulate = color
	_flash = seconds


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and not _over:
			message.text = ""


func _on_spotted() -> void:
	_end("REPÉRÉ !\n" + ("Touche REJOUER" if _touch else "Appuie sur R pour recommencer"), Color(1, 0.25, 0.2))


func _on_exit(body: Node3D) -> void:
	if body != player or _over:
		return
	var missing := _total_masks() - player.masks
	if missing > 0:
		_show("Porte fermée : il manque %d masque%s !" % [missing, "s" if missing > 1 else ""], Color(1, 0.8, 0.3), 2.5)
		return
	for g in guards:
		g.set_physics_process(false)
	_won = true
	var hint := "Touche l'écran" if _touch else "Appuie sur E"
	if current < Levels.LEVELS.size() - 1:
		_end("NIVEAU RÉUSSI !\n%s pour le niveau suivant" % hint, Color(0.3, 1, 0.4))
	else:
		_end("BRAVO ! Tu as dévalisé tout le musée !\n%s pour rejouer depuis le début" % hint, Color(1, 0.85, 0.3))
	if _pad:
		_pad.hide()
		_pad.set_process_input(false) # le prochain toucher passe au niveau suivant


func _end(text: String, color: Color) -> void:
	if _over:
		return
	_over = true
	player.enabled = false
	_show(text, color)


func _unhandled_input(event: InputEvent) -> void:
	if _won:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
				or (event is InputEventScreenTouch and event.pressed):
			current = (current + 1) % Levels.LEVELS.size()
			get_tree().reload_current_scene()
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
