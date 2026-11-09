extends Node3D

@onready var player: MuseumPlayer = $Player
@onready var guard: MuseumGuard = $Guard
@onready var message: Label = $HUD/Message

var _over := false


func _enter_tree() -> void:
	# Touches physiques : W/A/S/D = Z/Q/S/D sur clavier AZERTY.
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
		"crouch": [KEY_C], # pas Ctrl : sur Mac, Ctrl+flèches change de bureau
		"prone": [KEY_X],
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


var _touch := DisplayServer.is_touchscreen_available()


func _ready() -> void:
	# Relâche les actions restées "enfoncées" (ex. touche avalée par le système avant la mort).
	for a in InputMap.get_actions():
		Input.action_release(a)
	message.text = ""
	guard.player_spotted.connect(_on_spotted)
	$Exit.body_entered.connect(_on_exit)
	player.mask_taken.connect(_on_mask_taken)
	$HUD/Aide.text = "ZQSD : marcher   Maj : courir (bruyant)   C : s'accroupir   C en courant : glissade   X : ramper\n" \
		+ "Espace : roulade   E : prendre un masque   R : recommencer   Échap : libérer la souris\n" \
		+ "Objectif : vole les %d masques puis sors par la porte, sans te faire voir." % _total_masks()
	_counter.position = Vector2(16, 100) if not _touch else Vector2(16, 12)
	_counter.add_theme_font_size_override("font_size", 24)
	_counter.add_theme_constant_override("outline_size", 8)
	_counter.add_theme_color_override("font_outline_color", Color.BLACK)
	$HUD.add_child(_counter)
	_on_mask_taken(0)
	if _touch:
		var pad: Control = preload("res://musee/touch_controls.gd").new()
		pad.player = player
		$HUD.add_child(pad)
		$HUD/Aide.hide()
	$HUD.add_child(_popup) # au-dessus de la manette


var _counter := Label.new()
var _popup: Control = preload("res://musee/mask_popup.gd").new()
var _flash := 0.0


func _total_masks() -> int:
	return get_tree().get_nodes_in_group("vitrine").size()


func _on_mask_taken(total: int, vitrine: Node3D = null) -> void:
	_counter.text = "Masques : %d / %d" % [total, _total_masks()]
	if vitrine:
		# Laisse finir le geste de prise avant d'afficher la fiche du masque.
		get_tree().create_timer(0.8).timeout.connect(_popup.show_mask.bind(vitrine))
	# Porte rouge tant qu'il manque des masques, verte ensuite.
	var open := total >= _total_masks()
	var mat: StandardMaterial3D = $PorteSortie.mesh.material
	mat.albedo_color = Color(0.2, 0.8, 0.3) if open else Color(0.8, 0.15, 0.1)
	mat.emission = Color(0.1, 0.9, 0.3) if open else Color(0.9, 0.1, 0.05)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and not _over:
			message.text = ""


func _replay_hint() -> String:
	return "Touche REJOUER" if _touch else "Appuie sur R pour recommencer"


func _on_spotted() -> void:
	_end("REPÉRÉ !\n" + _replay_hint(), Color(1, 0.25, 0.2))


func _on_exit(body: Node3D) -> void:
	if body != player:
		return
	var missing := _total_masks() - player.masks
	if missing > 0:
		message.text = "Porte fermée : il manque %d masque%s !" % [missing, "s" if missing > 1 else ""]
		message.modulate = Color(1, 0.8, 0.3)
		_flash = 2.5
		return
	guard.set_physics_process(false)
	_end("RÉUSSI !\nTu as volé les %d masques sans être vu.\n%s" % [player.masks, _replay_hint()], Color(0.3, 1, 0.4))


func _end(text: String, color: Color) -> void:
	if _over:
		return
	_over = true
	player.enabled = false
	message.text = text
	message.modulate = color


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
