class_name MuseumPlayer
extends CharacterBody3D

signal mask_taken(total: int)

@export var walk_speed := 2.0
@export var run_speed := 5.5
@export var crouch_speed := 1.3
@export var roll_distance := 3.0
@export var slide_speed := 7.0
@export var mouse_sensitivity := 0.003
@export var body_color := Color(0.15, 0.15, 0.18)

enum State { NORMAL, ACTION, ROLL, SLIDE }

const EXTRA_ANIMS := preload("res://musee/persos/anims2.glb")
const COOLDOWN := 1.0

var state := State.NORMAL
var is_crouching := false
var is_running := false
var enabled := true
var masks := 0
var anim: AnimationPlayer

var _low := false
var _timer := 0.0
var _cooldown := 0.0
var _move_dir := Vector3.RIGHT
var _roll_speed := 0.0
var _slide_vel := 0.0
var _slide_phase := 0
var _vitrine: Node3D
var _grab_at := 0.0

@onready var visual: Node3D = $Visual
@onready var pivot: Node3D = $CameraPivot
@onready var shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pivot.rotation = Vector3(-0.6, -PI / 2, 0)
	visual.rotation.y = -PI / 2
	anim = setup_model($Visual/Model, body_color)
	add_animations(anim, EXTRA_ANIMS)


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
	_cooldown = maxf(0.0, _cooldown - delta)
	match state:
		State.NORMAL: _state_normal(delta)
		State.ACTION: _state_action(delta)
		State.ROLL: _state_roll(delta)
		State.SLIDE: _state_slide(delta)
	move_and_slide()


func _state_normal(delta: float) -> void:
	var input := Vector2.ZERO
	if enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, pivot.rotation.y) * Vector3(input.x, 0, input.y)
	var moving := dir.length() > 0.1
	if moving:
		_move_dir = dir.normalized()
	var crouch_held := enabled and Input.is_action_pressed("crouch")
	var run_held := enabled and Input.is_action_pressed("run")

	if enabled:
		# Glissade : s'accroupir pendant la course.
		if Input.is_action_just_pressed("crouch") and run_held and moving and _cooldown == 0.0:
			_start_slide()
			return
		if Input.is_action_just_pressed("roll"):
			try_roll()
		elif Input.is_action_just_pressed("interact"):
			try_interact()
		if state != State.NORMAL:
			return

	is_crouching = crouch_held
	is_running = run_held and not crouch_held and moving
	_set_low(crouch_held)
	var speed := crouch_speed if is_crouching else (run_speed if is_running else walk_speed)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if moving:
		_face(_move_dir, delta)

	if is_crouching:
		play_loop(anim, "Crouch_Fwd_Loop" if moving else "Crouch_Idle_Loop")
	elif is_running:
		play_loop(anim, "Sprint_Loop")
	else:
		play_loop(anim, "Walk_Loop" if moving else "Idle_Loop")


# --- Roulade ---------------------------------------------------------------

func try_roll() -> void:
	if state != State.NORMAL or _cooldown > 0.0 or not enabled:
		return
	_begin(State.ROLL)
	_timer = play_once(anim, "Roll")
	_roll_speed = roll_distance / maxf(_timer, 0.3)


func _state_roll(delta: float) -> void:
	velocity.x = _move_dir.x * _roll_speed
	velocity.z = _move_dir.z * _roll_speed
	_timer -= delta
	if _timer <= 0.1:
		_finish()


# --- Glissade --------------------------------------------------------------

func _start_slide() -> void:
	_begin(State.SLIDE)
	_slide_vel = slide_speed
	_slide_phase = 0
	_timer = play_once(anim, "Slide_Start")


func _state_slide(delta: float) -> void:
	_slide_vel = move_toward(_slide_vel, 0.0, 5.0 * delta)
	velocity.x = _move_dir.x * _slide_vel
	velocity.z = _move_dir.z * _slide_vel
	_timer -= delta
	if _slide_phase == 0 and _timer <= 0.0:
		_slide_phase = 1
		play_loop(anim, "Slide_Loop")
	if _slide_phase < 2 and _slide_vel < 2.0:
		_slide_phase = 2
		_timer = play_once(anim, "Slide_Exit")
	elif _slide_phase == 2 and _timer <= 0.1:
		_finish()


# --- Prendre un masque -----------------------------------------------------

func try_interact() -> void:
	if state != State.NORMAL or not enabled:
		return
	var v := nearest_vitrine()
	if v == null:
		return
	_move_dir = (v.global_position - global_position) * Vector3(1, 0, 1)
	_move_dir = _move_dir.normalized() if _move_dir.length() > 0.01 else Vector3.RIGHT
	_begin(State.ACTION)
	_vitrine = v
	_timer = play_once(anim, "Farm_Harvest" if is_crouching else "PickUp_Table")
	_grab_at = _timer * 0.5


func _state_action(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	_timer -= delta
	if _vitrine and _timer <= _grab_at:
		_vitrine.take_mask()
		_vitrine = null
		masks += 1
		mask_taken.emit(masks)
	if _timer <= 0.0:
		state = State.NORMAL


## Vitrine pleine la plus proche à portée de main, ou null.
func nearest_vitrine() -> Node3D:
	for v in get_tree().get_nodes_in_group("vitrine"):
		var flat: Vector3 = (v.global_position - global_position) * Vector3(1, 0, 1)
		if v.has_mask and flat.length() < 1.4:
			return v
	return null


# --- Utilitaires -----------------------------------------------------------

func _begin(new_state: State) -> void:
	state = new_state
	is_running = false
	_set_low(new_state != State.ACTION or is_crouching)
	visual.rotation.y = atan2(-_move_dir.x, -_move_dir.z)


func _finish() -> void:
	state = State.NORMAL
	_cooldown = COOLDOWN


func _face(dir: Vector3, delta: float) -> void:
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 12.0 * delta))


func _set_low(value: bool) -> void:
	if value == _low:
		return
	_low = value
	var h := 1.0 if value else 1.8
	(shape.shape as CapsuleShape3D).height = h
	shape.position.y = h / 2.0
	pivot.position.y = 0.9 if value else 1.5


## Point que le gardien doit voir pour repérer le joueur (plus bas quand il est baissé).
func get_target_point() -> Vector3:
	return global_position + Vector3(0, 0.6 if _low else 1.4, 0)


## Bruit fait par le joueur : 1 = course, 0.6 = roulade/glissade, 0 = silencieux.
func get_noise_level() -> float:
	if state == State.ROLL or state == State.SLIDE:
		return 0.6
	return 1.0 if is_running else 0.0


# --- Animations (partagées avec le gardien) --------------------------------

## Colore le mannequin et renvoie son AnimationPlayer.
static func setup_model(model: Node, color: Color) -> AnimationPlayer:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	return model.find_children("*", "AnimationPlayer", true, false)[0]


## Ajoute les animations d'un autre .glb (même squelette) à l'AnimationPlayer.
static func add_animations(player: AnimationPlayer, scene: PackedScene) -> void:
	var inst := scene.instantiate()
	var src: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := player.get_animation_library("")
	for n in src.get_animation_list():
		if not lib.has_animation(n):
			lib.add_animation(n, src.get_animation(n))
	inst.free()


## L'import Godot retire parfois le suffixe "_Loop" des noms d'animation.
static func _resolve(player: AnimationPlayer, anim_name: String) -> String:
	if player.has_animation(anim_name):
		return anim_name
	var short := anim_name.trim_suffix("_Loop")
	if player.has_animation(short):
		return short
	push_warning("Animation introuvable : %s" % anim_name)
	return ""


## Joue une animation en boucle avec un fondu de 0,2 s.
static func play_loop(player: AnimationPlayer, anim_name: String) -> void:
	if player == null:
		return
	anim_name = _resolve(player, anim_name)
	if anim_name.is_empty() or player.current_animation == anim_name:
		return
	player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	player.play(anim_name, 0.2)


## Joue une animation une seule fois et renvoie sa durée.
static func play_once(player: AnimationPlayer, anim_name: String) -> float:
	anim_name = _resolve(player, anim_name)
	if anim_name.is_empty():
		return 0.5
	var a := player.get_animation(anim_name)
	a.loop_mode = Animation.LOOP_NONE
	player.play(anim_name, 0.15)
	player.seek(0.0, true)
	return a.length
