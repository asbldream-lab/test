class_name MuseumPlayer
extends CharacterBody3D

@export var walk_speed := 2.0
@export var run_speed := 5.5
@export var crouch_speed := 1.3
@export var mouse_sensitivity := 0.003
@export var body_color := Color(0.15, 0.15, 0.18)

var is_crouching := false
var is_running := false
var enabled := true
var anim: AnimationPlayer

@onready var visual: Node3D = $Visual
@onready var pivot: Node3D = $CameraPivot
@onready var shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pivot.rotation = Vector3(-0.6, -PI / 2, 0)
	visual.rotation.y = -PI / 2
	anim = setup_model($Visual/Model, body_color)


## Colore le mannequin et renvoie son AnimationPlayer (utilisé aussi par le gardien).
static func setup_model(model: Node, color: Color) -> AnimationPlayer:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	return model.find_children("*", "AnimationPlayer", true, false)[0]


## Joue une animation en boucle avec un fondu de 0,2 s.
static func play_loop(player: AnimationPlayer, anim_name: String) -> void:
	if player == null:
		return
	# L'import Godot retire parfois le suffixe "_Loop" des noms d'animation.
	if not player.has_animation(anim_name):
		anim_name = anim_name.trim_suffix("_Loop")
	if not player.has_animation(anim_name):
		push_warning("Animation introuvable : %s. Dispo : %s" % [anim_name, player.get_animation_list()])
		return
	if player.current_animation == anim_name:
		return
	var a := player.get_animation(anim_name)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR
	player.play(anim_name, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Tourne la caméra (souris ou glissement du doigt).
func rotate_camera(relative: Vector2) -> void:
	pivot.rotation.y -= relative.x * mouse_sensitivity
	pivot.rotation.x = clampf(pivot.rotation.x - relative.y * mouse_sensitivity, -1.2, 0.15)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var input := Vector2.ZERO
	if enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	_set_crouch(enabled and Input.is_action_pressed("crouch"))
	is_running = enabled and Input.is_action_pressed("run") and not is_crouching and input.length() > 0.1

	var speed := crouch_speed if is_crouching else (run_speed if is_running else walk_speed)
	# Déplacement relatif à l'orientation de la caméra.
	var dir := (Basis(Vector3.UP, pivot.rotation.y) * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	var moving := dir.length() > 0.1
	if moving:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 12.0 * delta))

	if is_crouching:
		play_loop(anim, "Crouch_Fwd_Loop" if moving else "Crouch_Idle_Loop")
	elif is_running:
		play_loop(anim, "Sprint_Loop")
	else:
		play_loop(anim, "Walk_Loop" if moving else "Idle_Loop")


func _set_crouch(value: bool) -> void:
	if value == is_crouching:
		return
	is_crouching = value
	var h := 1.0 if value else 1.8
	(shape.shape as CapsuleShape3D).height = h
	shape.position.y = h / 2.0
	pivot.position.y = 0.9 if value else 1.5


## Point que le gardien doit voir pour repérer le joueur (plus bas quand accroupi).
func get_target_point() -> Vector3:
	return global_position + Vector3(0, 0.6 if is_crouching else 1.4, 0)
