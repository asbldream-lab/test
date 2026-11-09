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
@export var detect_time := 0.8
@export var spin_speed := 0.0 ## Si non nul : tourne sur place (rad/s) au lieu de patrouiller.
@export var start_index := 0 ## Point de ronde de départ. ## Secondes pour repérer le joueur à distance moyenne.

const RAY_MASK := 1 | 2 # monde + joueur (le verre des vitrines est ignoré)

var player: MuseumPlayer
var _index := 0
var _wait := 0.0
var _suspicion := 0.0
var _investigate := 0.0
var _look_target := Vector3.ZERO
var _done := false
var _cone_mat := ShaderMaterial.new()
var sees_player := false ## Le gardien voit le joueur en ce moment.
const GLOW := preload("res://musee/glow.gdshader")
var _anim: AnimationPlayer
var _alarm_flash := 0.0

@onready var cone: MeshInstance3D = $VisionCone
@onready var alert: Label3D = $Alert


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as MuseumPlayer
	_index = start_index
	_anim = MuseumPlayer.setup_model($Visual/Model, body_color)
	_dress_up()
	_build_cone()


# --- Uniforme et accessoires ---------------------------------------------------

const UNIFORM := preload("res://musee/uniform.gdshader")

var _skel: Skeleton3D
var _bone_head := -1
var _bone_chest := -1
var _bone_hand := -1
var _cap := Node3D.new()
var _badge := MeshInstance3D.new()
var _torch := Node3D.new()


## Habille le mannequin en gardien : uniforme, casquette, badge, lampe de poche.
func _dress_up() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = UNIFORM
	for m in $Visual/Model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	_skel = $Visual/Model.find_children("*", "Skeleton3D", true, false)[0]
	_bone_head = _skel.find_bone("Head")
	_bone_chest = _skel.find_bone("spine_03")
	_bone_hand = _skel.find_bone("hand_r")

	var navy := _std(Color(0.06, 0.08, 0.18), 0.6)
	var black := _std(Color(0.02, 0.02, 0.02), 0.3)
	_cap.add_child(_mesh(_cyl(0.13, 0.14, 0.09), navy, Vector3.ZERO))
	_cap.add_child(_mesh(_boxm(Vector3(0.2, 0.015, 0.12)), black, Vector3(0, -0.035, -0.15)))
	var gold := _std(Color(0.9, 0.72, 0.25), 0.25)
	gold.metallic = 0.9
	_cap.add_child(_mesh(_boxm(Vector3(0.05, 0.04, 0.01)), gold, Vector3(0, 0.0, -0.135)))
	_badge.mesh = _boxm(Vector3(0.06, 0.07, 0.01))
	_badge.material_override = gold
	# Lampe de poche : corps noir + verre lumineux.
	_torch.add_child(_mesh(_cyl(0.025, 0.03, 0.22), black, Vector3.ZERO, Vector3(-90, 0, 0)))
	var lens := _std(Color(1, 0.95, 0.8), 0.1)
	lens.emission_enabled = true
	lens.emission = Color(1, 0.95, 0.75)
	lens.emission_energy_multiplier = 4.0
	_torch.add_child(_mesh(_cyl(0.035, 0.035, 0.02), lens, Vector3(0, 0, -0.11), Vector3(-90, 0, 0)))
	for n in [_cap, _badge, _torch]:
		n.top_level = true # placés à la main chaque image (suivent les os, orientation du corps)
		add_child(n)
	$Lampe.top_level = true
	$Lampe.spot_angle_attenuation = 0.8
	# Faisceau visible (halo dans l'air) qui part de la lampe.
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.04
	beam_mesh.bottom_radius = 1.4
	beam_mesh.height = 5.0
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	beam.mesh = beam_mesh
	var bm := ShaderMaterial.new()
	bm.shader = GLOW
	bm.set_shader_parameter("mode", 1)
	bm.set_shader_parameter("strength", 0.1)
	bm.set_shader_parameter("tint", Color(1, 0.92, 0.7))
	bm.set_shader_parameter("beam_length", 5.0)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.rotation_degrees.x = 90
	beam.position.z = -2.5
	$Lampe.add_child(beam)


func _process(_delta: float) -> void:
	if _skel == null:
		return
	var yaw := Basis(Vector3.UP, rotation.y)
	var fwd := -yaw.z
	var bone := func(i: int) -> Vector3: return _skel.global_transform * _skel.get_bone_global_pose(i).origin
	_cap.global_transform = Transform3D(yaw, bone.call(_bone_head) + Vector3.UP * 0.2 + fwd * 0.02)
	_badge.global_transform = Transform3D(yaw, bone.call(_bone_chest) + Vector3.UP * 0.06 + fwd * 0.14 - yaw.x * 0.09)
	# Lampe dans la main droite, faisceau stable dans la direction du regard, un peu vers le bas.
	var aim := yaw * Basis(Vector3.RIGHT, deg_to_rad(-12))
	var hand: Vector3 = bone.call(_bone_hand) + fwd * 0.08
	_torch.global_transform = Transform3D(aim, hand)
	$Lampe.global_transform = Transform3D(aim, hand + aim * Vector3(0, 0, -0.13))


func _std(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	return c


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi


## Niveau de soupçon (0..1), pour la jauge de visibilité.
func get_suspicion() -> float:
	return clampf(_suspicion, 0.0, 1.0)


func _build_cone() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(view_angle / 2.0)
	var steps := 20
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		st.set_uv(Vector2(0, (i + 0.5) / steps))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(1, float(i) / steps))
		st.add_vertex(Vector3(sin(a0), 0, -cos(a0)) * view_distance)
		st.set_uv(Vector2(1, float(i + 1) / steps))
		st.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * view_distance)
	cone.mesh = st.commit()
	_cone_mat.shader = GLOW # lumière douce qui s'estompe vers les bords et au loin
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
	if spin_speed != 0.0:
		velocity.x = 0
		velocity.z = 0
		rotation.y += spin_speed * delta
		return
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
	sees_player = _can_see_player()
	if sees_player:
		var dist := global_position.distance_to(player.global_position)
		var closeness := lerpf(2.0, 0.6, clampf(dist / view_distance, 0.0, 1.0))
		_suspicion += delta / detect_time * closeness * player.get_visibility()
		_investigate = maxf(_investigate, 0.4)
		_look_target = player.global_position
	else:
		_suspicion = maxf(0.0, _suspicion - delta * 0.5)

	var s := clampf(_suspicion, 0, 1)
	_cone_mat.set_shader_parameter("tint", Color(1, 0.85, 0.5).lerp(Color(1, 0.15, 0.1), s))
	_cone_mat.set_shader_parameter("strength", lerpf(0.22, 0.5, s))
	alert.text = "?!" if _alarm_flash > 0.0 else ("?" if _suspicion > 0.05 else "")

	if _suspicion >= 1.0:
		_done = true
		alert.text = "!"
		alert.modulate = Color.RED
		_face(player.global_position - global_position, 1.0, 1.0)
		player_spotted.emit()
