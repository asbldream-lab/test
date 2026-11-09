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
		+ "Objectif : atteins la porte verte sans te faire voir. Bonus : vole les %d masques !" % _total_masks()
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
	var floor_mat := _parquet()
	var wall_mat := _mat(Color(0.5, 0.17, 0.15), 0.85)
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
	_box(Vector3(0, WALL_H + 0.1, 0), Vector3(w + 0.8, 0.2, d + 0.8), _mat(Color(0.82, 0.78, 0.7), 0.9)) # plafond
	_decor(w, d)

	_door(_data.entry, _mat(Color(0.3, 0.18, 0.1), 0.8))
	_door(_data.exit, _exit_mat)
	_exit_area(_data.exit)
	_paintings(w, d)

	_lighting(w, d)

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
			# Spot de galerie qui éclaire le tableau depuis le plafond.
			var spot := SpotLight3D.new()
			spot.light_color = Color(1, 0.9, 0.75)
			spot.light_energy = 2.0
			spot.spot_range = 3.2
			spot.spot_angle = 28
			spot.position = Vector3(0, 1.5, 1.1)
			spot.rotation_degrees = Vector3(-55, 0, 0)
			holder.add_child(spot)
			add_child(holder)


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
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.25, 0.22, 0.2)
	env.fog_density = 0.008
	var fixture := _emissive(Color(1, 0.9, 0.7), 3.0)
	var nx := maxi(1, roundi(w / 7.0))
	var nz := maxi(1, roundi(d / 7.0))
	for ix in nx:
		for iz in nz:
			var p := Vector3((ix + 0.5) * w / nx - w / 2, WALL_H - 0.05, (iz + 0.5) * d / nz - d / 2)
			add_child(_mesh_at(_cylm(0.35, 0.06), fixture, p))
			var light := OmniLight3D.new()
			light.position = p - Vector3(0, 0.4, 0)
			light.light_color = Color(1, 0.88, 0.7)
			light.light_energy = 0.95
			light.omni_range = 7.5
			light.omni_attenuation = 1.4
			add_child(light)


func _decor(w: float, d: float) -> void:
	# Plinthes sombres au bas des murs extérieurs.
	var base := _mat(Color(0.15, 0.08, 0.06), 0.5)
	for p in [[Vector3(0, 0.08, -d / 2 + 0.025), Vector3(w, 0.16, 0.05)], [Vector3(0, 0.08, d / 2 - 0.025), Vector3(w, 0.16, 0.05)],
			[Vector3(-w / 2 + 0.025, 0.08, 0), Vector3(0.05, 0.16, d)], [Vector3(w / 2 - 0.025, 0.08, 0), Vector3(0.05, 0.16, d)]]:
		add_child(_mesh_at(_boxm(p[1]), base, p[0]))
	# Tapis.
	var rug := _mat(Color(0.35, 0.06, 0.07), 1.0)
	var rug_border := _mat(Color(0.75, 0.6, 0.3), 1.0)
	for r in _data.rugs:
		add_child(_mesh_at(_boxm(Vector3(r[2], 0.012, r[3])), rug_border, Vector3(r[0], 0.006, r[1])))
		add_child(_mesh_at(_boxm(Vector3(r[2] - 0.2, 0.014, r[3] - 0.2)), rug, Vector3(r[0], 0.008, r[1])))
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
		add_child(bench)
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
		add_child(plant)
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
		add_child(holder)
	# Panneau SORTIE lumineux au-dessus de la porte de sortie.
	var e: Array = _data.exit
	var sign_holder := Node3D.new()
	var inward := _inward(e[2])
	sign_holder.position = Vector3(e[0], 2.85, e[1]) + inward * 0.06
	sign_holder.rotation.y = atan2(inward.x, inward.z)
	sign_holder.add_child(_mesh_at(_boxm(Vector3(0.9, 0.3, 0.06)), _emissive(Color(0.1, 0.8, 0.3), 2.5), Vector3.ZERO))
	var txt := Label3D.new()
	txt.text = "SORTIE"
	txt.font_size = 48
	txt.pixel_size = 0.004
	txt.position.z = 0.035
	txt.outline_size = 0
	sign_holder.add_child(txt)
	add_child(sign_holder)
	# Caméras de surveillance (décor) dans deux coins.
	var cam_mat := _mat(Color(0.85, 0.85, 0.85), 0.4)
	for c in [Vector2(-1, -1), Vector2(1, 1)]:
		var cam := Node3D.new()
		var cpos := Vector3(c.x * (w / 2 - 0.35), WALL_H - 0.4, c.y * (d / 2 - 0.35))
		cam.transform = Transform3D(Basis.looking_at(Vector3.ZERO - cpos), cpos) # vise le centre
		cam.add_child(_mesh_at(_boxm(Vector3(0.18, 0.15, 0.4)), cam_mat, Vector3.ZERO))
		cam.add_child(_mesh_at(_boxm(Vector3(0.05, 0.05, 0.02)), _emissive(Color(1, 0.1, 0.1), 4.0), Vector3(0.05, 0.05, -0.21)))
		add_child(cam)


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
	_exit_mat.albedo_color = Color(0.2, 0.8, 0.3) # sortie toujours ouverte
	_exit_mat.emission = Color(0.1, 0.9, 0.3)


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
	for g in guards:
		g.set_physics_process(false)
	_won = true
	var score := "Masques volés : %d / %d" % [player.masks, _total_masks()]
	var last := current >= Levels.LEVELS.size() - 1
	if last:
		_end("BRAVO ! Tu as traversé tout le musée !\n%s\nRetour au niveau 1..." % score, Color(1, 0.85, 0.3))
	else:
		_end("NIVEAU %d RÉUSSI !\n%s\nNiveau suivant..." % [current + 1, score], Color(0.3, 1, 0.4))
	if _pad:
		_pad.hide()
	# Téléportation automatique vers le niveau suivant.
	await get_tree().create_timer(4.0 if last else 2.5).timeout
	current = (current + 1) % Levels.LEVELS.size()
	get_tree().reload_current_scene()


func _end(text: String, color: Color) -> void:
	if _over:
		return
	_over = true
	player.enabled = false
	_show(text, color)


func _unhandled_input(event: InputEvent) -> void:
	if not _won and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
