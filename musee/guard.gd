class_name MuseumGuard
extends CharacterBody3D

signal player_spotted

@export var waypoints: Array[Vector3] = []
@export var speed := 1.6
@export var body_color := Color(0.12, 0.16, 0.38)
@export var wait_time := 1.5
@export var view_distance := 7.0
@export var view_angle := 70.0 ## Angle total du cône de vision, en degrés.
@export var hearing_radius := 5.0 ## Distance à laquelle il entend le joueur courir.
@export var detect_time := 0.8 ## Secondes pour repérer le joueur à distance moyenne.

const RAY_MASK := 1 | 2 # monde + joueur (le verre des vitrines est ignoré)

var player: MuseumPlayer
var _index := 0
var _wait := 0.0
var _suspicion := 0.0
var _investigate := 0.0
var _look_target := Vector3.ZERO
var _done := false
var _cone_mat := StandardMaterial3D.new()
var _anim: AnimationPlayer
var _alarm_flash := 0.0

@onready var cone: MeshInstance3D = $VisionCone
@onready var alert: Label3D = $Alert


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as MuseumPlayer
	_anim = MuseumPlayer.setup_model($Visual/Model, body_color)
	_build_cone()


func _build_cone() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(view_angle / 2.0)
	var steps := 20
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0, -cos(a0)) * view_distance)
		st.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * view_distance)
	cone.mesh = st.commit()
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = _cone_mat


func _physics_process(delta: float) -> void:
	if _done or player == null:
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	# Ouïe : un joueur qui court à proximité attire le regard du gardien.
	var flat_to_player := player.global_position - global_position
	flat_to_player.y = 0
	if flat_to_player.length() < hearing_radius * player.get_noise_level():
		_investigate = 2.5
		_look_target = player.global_position

	if _investigate > 0:
		_investigate -= delta
		velocity.x = 0
		velocity.z = 0
		_face(_look_target - global_position, delta, 6.0)
	else:
		_patrol(delta)

	move_and_slide()
	var walking := Vector2(velocity.x, velocity.z).length() > 0.1
	MuseumPlayer.play_loop(_anim, "Walk_Formal_Loop" if walking else "Idle_Torch_Loop")
	_update_vision(delta)


func _patrol(delta: float) -> void:
	if waypoints.is_empty():
		return
	var d := waypoints[_index] - global_position
	d.y = 0
	if d.length() < 0.15:
		_index = (_index + 1) % waypoints.size()
		_wait = wait_time
		velocity.x = 0
		velocity.z = 0
		return
	if _wait > 0:
		# Pause : il se tourne lentement vers le prochain point.
		_wait -= delta
		velocity.x = 0
		velocity.z = 0
		_face(d, delta, 2.5)
		return
	var dir := d.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(d, delta, 6.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, rate * delta))


func _can_see_player() -> bool:
	var eye := global_position + Vector3(0, 1.6, 0)
	var target := player.get_target_point()
	var flat := target - eye
	flat.y = 0
	if flat.length() > view_distance or flat.length() < 0.01:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0
	if forward.angle_to(flat.normalized()) > deg_to_rad(view_angle / 2.0):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, RAY_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


## Le gardien remarque les vitrines vides dans son champ de vision et devient plus vigilant.
func _check_vitrines() -> void:
	var forward := -global_transform.basis.z
	forward.y = 0
	for v in get_tree().get_nodes_in_group("vitrine"):
		if v.has_mask or v.noticed:
			continue
		var flat: Vector3 = (v.global_position - global_position) * Vector3(1, 0, 1)
		if flat.length() < view_distance and forward.angle_to(flat) < deg_to_rad(view_angle / 2.0):
			v.noticed = true
			_investigate = 2.5
			_look_target = v.global_position
			_alarm_flash = 1.5
			speed *= 1.15
			view_distance += 0.8
			_build_cone()


func _update_vision(delta: float) -> void:
	_check_vitrines()
	_alarm_flash = maxf(0.0, _alarm_flash - delta)
	if _can_see_player():
		var dist := global_position.distance_to(player.global_position)
		var closeness := lerpf(2.0, 0.6, clampf(dist / view_distance, 0.0, 1.0))
		_suspicion += delta / detect_time * closeness
		_investigate = maxf(_investigate, 0.4)
		_look_target = player.global_position
	else:
		_suspicion = maxf(0.0, _suspicion - delta * 0.5)

	_cone_mat.albedo_color = Color(1, 0.9, 0.3, 0.22).lerp(Color(1, 0.1, 0.1, 0.4), clampf(_suspicion, 0, 1))
	alert.text = "?!" if _alarm_flash > 0.0 else ("?" if _suspicion > 0.05 else "")

	if _suspicion >= 1.0:
		_done = true
		alert.text = "!"
		alert.modulate = Color.RED
		_face(player.global_position - global_position, 1.0, 1.0)
		player_spotted.emit()
