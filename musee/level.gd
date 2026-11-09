extends Node3D
## Construit tout le musée d'un seul tenant à partir de levels.gd : les salles sont
## placées côte à côte et reliées par des couloirs (aucun chargement, retour possible).
## Gère la salle courante, la mise en veille des salles éloignées, la réapparition et la victoire.

const VITRINE := preload("res://musee/vitrine.tscn")
const GUARD := preload("res://musee/guard.tscn")
const WALL_H := 4.0

var current := 0 ## Salle en cours de construction (graine des tableaux, numéro).
const CORRIDOR := 4.0

@onready var player: MuseumPlayer = $Player
@onready var message: Label = $HUD/Message

var guards: Array[MuseumGuard] = []
var _data: Dictionary
var _over := false
var _won := false
var _touch := DisplayServer.is_touchscreen_available()
var _hud: Control = preload("res://musee/hud.gd").new()
var _popup: Control = preload("res://musee/mask_popup.gd").new()
var _pad: Control
var _flash := 0.0
var _exit_mat := StandardMaterial3D.new()
var _root: Node3D = self
var _rooms: Array[Dictionary] = [] ## {root, origin, size, guards, spawn, yaw, name}
var _room := -1 ## salle où se trouve le joueur
var _mobile := DisplayServer.is_touchscreen_available()
var _cull_timer := 0.0


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
	if _mobile:
		# Réglages allégés pour téléphone.
		get_viewport().msaa_3d = Viewport.MSAA_2X
		get_viewport().scaling_3d_scale = 0.8
	_build_museum()
	player.mask_taken.connect(_on_mask_taken)

	$HUD/Aide.hide()
	$HUD.add_child(_hud)
	$HUD.move_child(_hud, 0) # sous le message, la manette et la fiche

	message.add_theme_font_override("font", preload("res://musee/fonts/Cinzel.ttf"))
	message.add_theme_font_size_override("font_size", 40)
	message.add_theme_constant_override("shadow_offset_y", 3)
	message.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_on_mask_taken(0)
	if _touch:
		_pad = preload("res://musee/touch_controls.gd").new()
		_pad.player = player
		$HUD.add_child(_pad)
	$HUD.add_child(_popup) # au-dessus de la manette
	var r0: Dictionary = _rooms[0]
	player.global_position = r0.spawn
	player.set_facing(r0.yaw)
	_update_room(true)


# --- Construction du niveau -------------------------------------------------

func _build_museum() -> void:
	var origin := Vector3.ZERO
	var count := Levels.LEVELS.size()
	for i in count:
		_data = Levels.LEVELS[i]
		current = i
		if i > 0:
			# Le couloir part de la sortie de la salle précédente.
			var prev: Dictionary = Levels.LEVELS[i - 1]
			var out := -_inward(prev.exit[2])
			var a: Vector3 = _rooms[i - 1].origin + Vector3(prev.exit[0], 0, prev.exit[1])
			var b := a + out * CORRIDOR
			_root = self
			_corridor(a, b)
			origin = b - Vector3(_data.entry[0], 0, _data.entry[1])
		_root = Node3D.new()
		_root.name = "Salle%d" % (i + 1)
		_root.position = origin
		add_child(_root)
		var first_guard := guards.size()
		_build(i == 0, i == count - 1)
		var spawn: Vector3
		var yaw: float
		if i == 0:
			spawn = origin + Vector3(_data.spawn[0], 0, _data.spawn[1])
			yaw = deg_to_rad(_data.spawn[2])
		else:
			var inw := _inward(_data.entry[2])
			spawn = origin + Vector3(_data.entry[0], 0, _data.entry[1]) + inw * 1.5
			yaw = atan2(-inw.x, -inw.z)
		_rooms.append({"root": _root, "origin": origin, "size": _data.size, "name": _data.name,
			"guards": guards.slice(first_guard), "spawn": spawn, "yaw": yaw})
	_root = self


## Couloir entre deux salles (de a à b, au sol), éclairé.
func _corridor(a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var mid := (a + b) / 2
	var side := Vector3(-dir.z, 0, dir.x)
	var clen := a.distance_to(b)
	var along_x := absf(dir.x) > 0.5
	var floor_mat := _smat(0, Color(0.27, 0.15, 0.08), Color(0.48, 0.3, 0.16))
	var wall_mat := _smat(1, Color(0.33, 0.05, 0.06), Color(0.5, 0.12, 0.1))
	var fsize := Vector3(clen, 0.2, 2.4) if along_x else Vector3(2.4, 0.2, clen)
	_box(mid + Vector3(0, -0.1, 0), fsize, floor_mat)
	_box(mid + Vector3(0, WALL_H + 0.1, 0), fsize + Vector3(0.8, 0, 0.8) * Vector3(0 if along_x else 1, 0, 1 if along_x else 0), _smat(4, Color(0.32, 0.27, 0.22), Color(0.16, 0.12, 0.09)))
	for sgn in [-1.0, 1.0]:
		var wsize := Vector3(clen, WALL_H, 0.4) if along_x else Vector3(0.4, WALL_H, clen)
		_box(mid + side * sgn * 1.4 + Vector3(0, WALL_H / 2, 0), wsize, wall_mat)
	var light := OmniLight3D.new()
	light.position = mid + Vector3(0, WALL_H - 0.5, 0)
	light.light_color = Color(1, 0.88, 0.7)
	light.light_energy = 0.8
	light.omni_range = 5.0
	add_child(light)


## Mur extérieur d'un côté, avec une ouverture (et un linteau) à chaque position de `gaps`.
func _outer_wall(side: String, w: float, d: float, mat: Material, gaps: Array) -> void:
	var horiz := side == "N" or side == "S"
	var half_len := (w + 0.8) / 2.0 if horiz else d / 2.0
	var fixed: float
	if horiz:
		fixed = -(d / 2 + 0.2) if side == "N" else d / 2 + 0.2
	else:
		fixed = -(w / 2 + 0.2) if side == "W" else w / 2 + 0.2
	var cuts: Array[float] = [-half_len]
	gaps.sort()
	for g in gaps:
		cuts.append(g - 1.2)
		cuts.append(g + 1.2)
	cuts.append(half_len)
	for k in range(0, cuts.size(), 2):
		if cuts[k + 1] - cuts[k] > 0.05:
			_wall_piece(horiz, fixed, (cuts[k] + cuts[k + 1]) / 2.0, cuts[k + 1] - cuts[k], 0.0, mat)
	for g in gaps:
		_wall_piece(horiz, fixed, g, 2.4, 2.6, mat) # linteau au-dessus de l'ouverture


func _wall_piece(horiz: bool, fixed: float, mid: float, length: float, y0: float, mat: Material) -> void:
	var h := WALL_H - y0
	if horiz:
		_box(Vector3(mid, y0 + h / 2, fixed), Vector3(length, h, 0.4), mat)
	else:
		_box(Vector3(fixed, y0 + h / 2, mid), Vector3(0.4, h, length), mat)


func _build(first: bool, last: bool) -> void:
	var w: float = _data.size.x
	var d: float = _data.size.y
	var floor_mat := _smat(0, Color(0.27, 0.15, 0.08), Color(0.48, 0.3, 0.16))
	var wall_mat := _smat(1, Color(0.33, 0.05, 0.06), Color(0.5, 0.12, 0.1))
	var col_mat := _smat(2, Color(0.93, 0.91, 0.87), Color(0.45, 0.43, 0.42))
	_exit_mat.emission_enabled = true

	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_mat)
	# Murs extérieurs puis cloisons intérieures.
	# Ouvertures : vers la salle précédente (entrée) et la suivante (sortie).
	var gaps := {"N": [], "S": [], "E": [], "W": []}
	if not first:
		gaps[_data.entry[2]].append(_data.entry[0] if _data.entry[2] in ["N", "S"] else _data.entry[1])
	if not last:
		gaps[_data.exit[2]].append(_data.exit[0] if _data.exit[2] in ["N", "S"] else _data.exit[1])
	for side in ["N", "S", "E", "W"]:
		_outer_wall(side, w, d, wall_mat, gaps[side])
	for r in _data.walls:
		_box(Vector3(r[0], WALL_H / 2, r[1]), Vector3(r[2], WALL_H, r[3]), wall_mat)
	for c in _data.columns:
		_column(Vector3(c[0], 0, c[1]), col_mat)
	_box(Vector3(0, WALL_H + 0.1, 0), Vector3(w + 0.8, 0.2, d + 0.8), _smat(4, Color(0.32, 0.27, 0.22), Color(0.16, 0.12, 0.09))) # plafond à caissons
	_decor(w, d)

	if first:
		_door(_data.entry, _mat(Color(0.3, 0.18, 0.1), 0.8))
	if last:
		_door(_data.exit, _exit_mat)
		_exit_area(_data.exit)
	_paintings(w, d)

	_lighting(w, d)

	var plinth_mat := _smat(2, Color(0.07, 0.06, 0.06), Color(0.6, 0.48, 0.3))
	for v in _data.vitrines:
		var m: Array = Levels.MASKS[v[3]]
		var vit := VITRINE.instantiate()
		vit.mask_id = v[3]
		vit.face_color = m[3]
		vit.accent_color = m[4]
		vit.position = Vector3(v[0], 0, v[1])
		vit.rotation.y = deg_to_rad(v[2])
		_root.add_child(vit)
		vit.get_node("Socle/Mesh").material_override = plinth_mat # socle en marbre noir veiné d'or
		var sp: SpotLight3D = vit.get_node("Spot")
		sp.light_energy = 1.6
		sp.spot_angle = 32
		sp.spot_angle_attenuation = 0.7 # bord de lumière doux

	for g in _data.guards:
		var guard: MuseumGuard = GUARD.instantiate()
		var pts: Array[Vector3] = []
		for p in g.wp:
			pts.append(_root.position + Vector3(p[0], 0, p[1])) # points de ronde en coordonnées monde
		guard.waypoints = pts
		guard.start_index = g.get("start", 0)
		guard.spin_speed = g.get("spin", 0.0)
		guard.position = pts[guard.start_index] - _root.position
		_root.add_child(guard)
		guard.player_spotted.connect(_on_spotted)
		guards.append(guard)
		if _mobile:
			guard.get_node("Lampe").shadow_enabled = false


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var nx := maxi(1, ceili(size.x / 6.0))
	var nz := maxi(1, ceili(size.z / 6.0))
	var piece := Vector3(size.x / nx, size.y, size.z / nz)
	for ix in nx:
		for iz in nz:
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.mesh.size = piece
			mesh.material_override = mat
			mesh.position = Vector3((ix + 0.5) * piece.x - size.x / 2, 0, (iz + 0.5) * piece.z - size.z / 2)
			body.add_child(mesh)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = size
	body.add_child(col)
	_root.add_child(body)


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
	_root.add_child(body)


## Tableaux sur les murs extérieurs (un tous les ~5 m), en évitant portes et cloisons.
## Toiles abstraites générées (dégradés) ; couleurs différentes à chaque niveau.
func _paintings(w: float, d: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + current
	var frame_mat := _mat(Color(0.78, 0.6, 0.25), 0.35)
	frame_mat.metallic = 0.6
	var doors: Array[Vector2] = [Vector2(_data.entry[0], _data.entry[1]), Vector2(_data.exit[0], _data.exit[1])]
	# Images fournies (png/jpg/webp) dans res://musee/tableaux/ : accrochées en priorité.
	var images: Array[Texture2D] = []
	var titles: Array[String] = []
	for f in ResourceLoader.list_directory("res://musee/tableaux/"):
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			images.append(load("res://musee/tableaux/" + f))
			titles.append(f.get_basename())
	var img_i := current * 5 # chaque niveau commence à une image différente
	for side in ["N", "S", "E", "W"]:
		var length := w if side in ["N", "S"] else d
		var count := int(length / 5.0)
		for i in count:
			var t := (i + 0.5) / count * length - length / 2.0
			var pos: Vector3 = {"N": Vector3(t, 2.2, -d / 2), "S": Vector3(t, 2.2, d / 2),
				"E": Vector3(w / 2, 2.2, t), "W": Vector3(-w / 2, 2.2, t)}[side]
			var flat := Vector2(pos.x, pos.z)
			if doors.any(func(p): return flat.distance_to(p) < 2.2):
				continue
			if _data.walls.any(func(r): return absf(pos.x - r[0]) < r[2] / 2 + 1.2 and absf(pos.z - r[1]) < r[3] / 2 + 1.2):
				continue
			var inward := _inward(side)
			var holder := Node3D.new()
			holder.position = pos + inward * 0.04
			holder.rotation.y = atan2(inward.x, inward.z) # +z local = vers la pièce
			var tex: Texture2D = null
			var title := "Œuvre anonyme"
			var size := Vector2(rng.randf_range(1.0, 1.8), rng.randf_range(0.8, 1.3))
			if not images.is_empty():
				tex = images[img_i % images.size()]
				title = titles[img_i % images.size()]
				img_i += 1
				var aspect := float(tex.get_width()) / tex.get_height()
				size = Vector2(1.2 * aspect, 1.2) if aspect <= 1.6 else Vector2(2.0, 2.0 / aspect)
				size += Vector2(0.16, 0.16) # place du cadre
			var frame := MeshInstance3D.new()
			frame.mesh = BoxMesh.new()
			frame.mesh.size = Vector3(size.x, size.y, 0.06)
			frame.material_override = frame_mat
			holder.add_child(frame)
			var canvas := MeshInstance3D.new()
			canvas.mesh = QuadMesh.new()
			canvas.mesh.size = size - Vector2(0.16, 0.16)
			canvas.position.z = 0.031
			if tex:
				canvas.material_override = _mat(Color.WHITE, 0.8)
				canvas.material_override.albedo_texture = tex
			else:
				canvas.material_override = _canvas(rng)
			holder.add_child(canvas)
			# Cartel sous le tableau.
			var plate := _mesh_at(_boxm(Vector3(0.42, 0.14, 0.02)), _mat(Color(0.92, 0.9, 0.84), 0.6), Vector3(0, -size.y / 2 - 0.25, 0.01))
			holder.add_child(plate)
			var label := Label3D.new()
			label.text = title
			label.font_size = 16
			label.pixel_size = 0.0015
			label.width = 260
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.modulate = Color(0.1, 0.08, 0.06)
			label.outline_size = 0
			label.position = Vector3(0, -size.y / 2 - 0.25, 0.022)
			holder.add_child(label)
			if _mobile and img_i % 2 == 0:
				_root.add_child(holder)
				continue
			# Spot de galerie qui éclaire le tableau depuis le plafond.
			var spot := SpotLight3D.new()
			spot.light_color = Color(1, 0.9, 0.75)
			spot.light_energy = 1.3
			spot.spot_range = 3.4
			spot.spot_angle = 38
			spot.spot_angle_attenuation = 0.7
			spot.position = Vector3(0, 1.5, 1.1)
			spot.rotation_degrees = Vector3(-55, 0, 0)
			holder.add_child(spot)
			_root.add_child(holder)


func _canvas(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.3, 0.9)))
	g.set_color(1, Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.3, 0.9)))
	g.add_point(rng.randf_range(0.3, 0.7), Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.9), rng.randf_range(0.4, 1.0)))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = rng.randi_range(0, 2) as GradientTexture2D.Fill # linéaire, radial ou carré
	tex.fill_from = Vector2(rng.randf(), rng.randf())
	tex.fill_to = Vector2(rng.randf(), rng.randf())
	var m := _mat(Color.WHITE, 0.8)
	m.albedo_texture = tex
	return m


# --- Décor et éclairage -------------------------------------------------------

func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cylm(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _mesh_at(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


const MUSEUM := preload("res://musee/museum.gdshader")


## Matière procédurale (voir museum.gdshader) : 0 parquet, 1 mur, 2 marbre, 3 tapis, 4 plafond.
func _smat(mode: int, a: Color, b: Color, c := Color(0.78, 0.6, 0.28)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MUSEUM
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("color_c", c)
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(c, 0.5)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Parquet : bruit étiré façon veinage du bois.
func _parquet() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.19, 0.11))
	ramp.set_color(1, Color(0.5, 0.33, 0.2))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var m := _mat(Color.WHITE, 0.4)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 1.5) # étiré dans un sens = lames de bois
	return m


## Ambiance de musée la nuit : plafonniers, halo léger, lumière chaude et sombre.
func _lighting(w: float, d: float) -> void:
	var env: Environment = $WorldEnvironment.environment
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_color = Color(0.45, 0.4, 0.38)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = not _mobile
	env.fog_light_color = Color(0.25, 0.22, 0.2)
	env.fog_density = 0.008
	var fixture := _emissive(Color(1, 0.9, 0.7), 3.0)
	var nx := maxi(1, roundi(w / 7.0))
	var nz := maxi(1, roundi(d / 7.0))
	for ix in nx:
		for iz in nz:
			var p := Vector3((ix + 0.5) * w / nx - w / 2, WALL_H - 0.05, (iz + 0.5) * d / nz - d / 2)
			_root.add_child(_mesh_at(_cylm(0.35, 0.06), fixture, p))
			var light := OmniLight3D.new()
			light.position = p - Vector3(0, 0.4, 0)
			light.light_color = Color(1, 0.88, 0.7)
			light.light_energy = 0.95
			light.omni_range = 7.5
			light.omni_attenuation = 1.4
			_root.add_child(light)


func _decor(w: float, d: float) -> void:
	# Tapis.
	for r in _data.rugs:
		var plane := PlaneMesh.new()
		plane.size = Vector2(r[2], r[3])
		var rug := _smat(3, Color(0.32, 0.04, 0.06), Color(0.12, 0.05, 0.12))
		rug.set_shader_parameter("rug_size", Vector2(r[2], r[3]))
		_root.add_child(_mesh_at(plane, rug, Vector3(r[0], 0.012, r[1])))
	# Bancs de musée.
	var wood := _mat(Color(0.3, 0.18, 0.1), 0.5)
	var metal := _mat(Color(0.1, 0.1, 0.1), 0.3)
	for b in _data.benches:
		var bench := StaticBody3D.new()
		bench.position = Vector3(b[0], 0, b[1])
		bench.rotation_degrees.y = b[2]
		bench.add_child(_mesh_at(_boxm(Vector3(1.8, 0.08, 0.5)), wood, Vector3(0, 0.45, 0)))
		for x in [-0.75, 0.75]:
			bench.add_child(_mesh_at(_boxm(Vector3(0.06, 0.42, 0.45)), metal, Vector3(x, 0.21, 0)))
		var col := CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		col.shape.size = Vector3(1.8, 0.5, 0.5)
		col.position.y = 0.25
		bench.add_child(col)
		_root.add_child(bench)
	# Plantes dans les coins.
	var pot := _mat(Color(0.6, 0.3, 0.2), 0.8)
	var leaves := _mat(Color(0.12, 0.3, 0.1), 0.9)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := Vector3(c.x * (w / 2 - 0.7), 0, c.y * (d / 2 - 0.7))
		var plant := StaticBody3D.new()
		plant.position = p
		plant.add_child(_mesh_at(_cylm(0.28, 0.5), pot, Vector3(0, 0.25, 0)))
		var foliage := SphereMesh.new()
		foliage.radius = 0.45
		foliage.height = 1.1
		plant.add_child(_mesh_at(foliage, leaves, Vector3(0, 0.95, 0)))
		var col := CollisionShape3D.new()
		col.shape = CylinderShape3D.new()
		col.shape.radius = 0.3
		col.shape.height = 1.4
		col.position.y = 0.7
		plant.add_child(col)
		_root.add_child(plant)
	# Cordons de sécurité devant une vitrine sur deux.
	var post_mat := _mat(Color(0.8, 0.65, 0.3), 0.3)
	post_mat.metallic = 0.8
	var rope := _mat(Color(0.55, 0.05, 0.08), 0.8)
	for i in range(0, _data.vitrines.size(), 2):
		var v: Array = _data.vitrines[i]
		var holder := Node3D.new()
		holder.position = Vector3(v[0], 0, v[1])
		holder.rotation_degrees.y = v[2]
		for x in [-0.75, 0.75]:
			holder.add_child(_mesh_at(_cylm(0.03, 0.9), post_mat, Vector3(x, 0.45, 1.0)))
		holder.add_child(_mesh_at(_boxm(Vector3(1.5, 0.03, 0.03)), rope, Vector3(0, 0.82, 1.0)))
		_root.add_child(holder)
	# Panneau SORTIE lumineux au-dessus de la porte de sortie.
	var e: Array = _data.exit
	var sign_holder := Node3D.new()
	var inward := _inward(e[2])
	sign_holder.position = Vector3(e[0], 2.85, e[1]) + inward * 0.06
	sign_holder.rotation.y = atan2(inward.x, inward.z)
	sign_holder.add_child(_mesh_at(_boxm(Vector3(0.9, 0.3, 0.06)), _emissive(Color(0.1, 0.8, 0.3), 2.5), Vector3.ZERO))
	var txt := Label3D.new()
	txt.text = "SORTIE" if current == Levels.LEVELS.size() - 1 else "SALLE %d" % (current + 2)
	txt.font_size = 48
	txt.pixel_size = 0.004
	txt.position.z = 0.035
	txt.outline_size = 0
	sign_holder.add_child(txt)
	_root.add_child(sign_holder)
	# Caméras de surveillance (décor) dans deux coins.
	var cam_mat := _mat(Color(0.85, 0.85, 0.85), 0.4)
	for c in [Vector2(-1, -1), Vector2(1, 1)]:
		var cam := Node3D.new()
		var cpos := Vector3(c.x * (w / 2 - 0.35), WALL_H - 0.4, c.y * (d / 2 - 0.35))
		cam.transform = Transform3D(Basis.looking_at(Vector3.ZERO - cpos), cpos) # vise le centre
		cam.add_child(_mesh_at(_boxm(Vector3(0.18, 0.15, 0.4)), cam_mat, Vector3.ZERO))
		cam.add_child(_mesh_at(_boxm(Vector3(0.05, 0.05, 0.02)), _emissive(Color(1, 0.1, 0.1), 4.0), Vector3(0.05, 0.05, -0.21)))
		_root.add_child(cam)


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
	_root.add_child(mesh)


func _exit_area(info: Array) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector3(info[0], 1.25, info[1]) + _inward(info[2]) * 0.8
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1.6, 2.5, 1.6)
	area.add_child(col)
	_root.add_child(area)
	area.body_entered.connect(_on_exit)


# --- Déroulement de la partie ----------------------------------------------

func _total_masks() -> int:
	var n := 0
	for l in Levels.LEVELS:
		n += l.vitrines.size()
	return n


func _on_mask_taken(total: int, vitrine: Node3D = null) -> void:
	_hud.set_masks(total, _total_masks())
	if vitrine:
		# Laisse finir le geste de prise avant d'afficher la fiche du masque.
		get_tree().create_timer(0.8).timeout.connect(_popup.show_mask.bind(vitrine))
	_exit_mat.albedo_color = Color(0.2, 0.8, 0.3) # sortie toujours ouverte
	_exit_mat.emission = Color(0.1, 0.9, 0.3)


## Salle contenant le joueur (marge de 0,5 m), ou -1 dans un couloir.
func _room_at(p: Vector3) -> int:
	for k in _rooms.size():
		var r: Dictionary = _rooms[k]
		var local: Vector3 = p - r.origin
		if absf(local.x) < r.size.x / 2 + 0.5 and absf(local.z) < r.size.y / 2 + 0.5:
			return k
	return -1


## Met à jour la salle courante et met en veille les salles éloignées (affichage + gardiens).
func _update_room(force := false) -> void:
	var k := _room_at(player.global_position)
	if k != -1 and (k != _room or force):
		_room = k
		var r: Dictionary = _rooms[k]
		_hud.setup(k, _rooms.size(), r.name, _touch)
		_show("Salle %d / %d\n%s" % [k + 1, _rooms.size(), r.name], Color(1, 0.9, 0.6), 2.5)
	for n in _rooms.size():
		var r: Dictionary = _rooms[n]
		var local: Vector3 = player.global_position - r.origin
		var dx := maxf(0.0, absf(local.x) - r.size.x / 2)
		var dz := maxf(0.0, absf(local.z) - r.size.y / 2)
		var active := n == _room or Vector2(dx, dz).length() < 8.0
		r.root.visible = active
		for g in r.guards:
			g.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _show(text: String, color: Color, seconds := 0.0) -> void:
	message.text = text
	message.modulate = color
	_flash = seconds


func _process(delta: float) -> void:
	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_cull_timer = 0.2
		_update_room()
	# Jauge de visibilité : soupçon le plus élevé parmi les gardiens.
	var vis := 0.0
	var seen := false
	for g in guards:
		vis = maxf(vis, g.get_suspicion())
		seen = seen or g.sees_player
	_hud.set_visibility(vis, seen)
	# Invite « Appuie sur E » quand un masque est à portée de main.
	var vit: Node3D = player.nearest_vitrine() if player.state == MuseumPlayer.State.NORMAL and not _over else null
	if vit:
		_hud.set_prompt("PRENDRE" if _touch else "E", ("Touche pour récupérer : " if _touch else "Appuie pour récupérer : ") + Levels.MASKS[vit.mask_id][0])
	else:
		_hud.set_prompt("", "")
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and not _over:
			message.text = ""


func _on_spotted() -> void:
	if _over:
		return
	_end("REPÉRÉ !\nRetour à l'entrée de la salle...", Color(1, 0.25, 0.2))
	await get_tree().create_timer(1.8).timeout
	_respawn()


## Réapparition à l'entrée de la salle en cours, sans rechargement (masques conservés).
func _respawn() -> void:
	var r: Dictionary = _rooms[maxi(_room, 0)]
	player.state = MuseumPlayer.State.NORMAL
	player.anim.speed_scale = 1.0
	player.velocity = Vector3.ZERO
	player.global_position = r.spawn
	player.set_facing(r.yaw)
	for g in guards:
		g.reset()
	player.enabled = true
	_over = false
	message.text = ""


func _on_exit(body: Node3D) -> void:
	if body != player or _over:
		return
	for g in guards:
		g.set_physics_process(false)
	_won = true
	if _pad:
		_pad.hide()
	_end("BRAVO ! Tu as traversé tout le musée !\nMasques récupérés : %d / %d\n%s" % [player.masks, _total_masks(),
		"Touche REJOUER" if _touch else "Appuie sur R pour rejouer"], Color(1, 0.85, 0.3))


func _end(text: String, color: Color) -> void:
	if _over:
		return
	_over = true
	player.enabled = false
	_show(text, color)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
