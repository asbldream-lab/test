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
		"crouch": [KEY_CTRL, KEY_C],
		"restart": [KEY_R],
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
	message.text = ""
	guard.player_spotted.connect(_on_spotted)
	$Exit.body_entered.connect(_on_exit)


func _on_spotted() -> void:
	_end("REPÉRÉ !\nAppuie sur R pour recommencer", Color(1, 0.25, 0.2))


func _on_exit(body: Node3D) -> void:
	if body == player:
		guard.set_physics_process(false)
		_end("RÉUSSI !\nTu as traversé la salle sans être vu.\nR pour rejouer", Color(0.3, 1, 0.4))


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
