@tool
extends Node3D
## Socle en bois + vitrine en verre + masque africain stylisé.

@export var face_color := Color(0.35, 0.2, 0.1):
	set(value):
		face_color = value
		_apply()
@export var accent_color := Color(0.95, 0.9, 0.8):
	set(value):
		accent_color = value
		_apply()


var has_mask := true
var noticed := false ## Le gardien a déjà remarqué que la vitrine est vide.


func _ready() -> void:
	add_to_group("vitrine")
	_apply()


## Le voleur prend le masque : la vitrine se retrouve ouverte et vide.
func take_mask() -> void:
	has_mask = false
	$Mask.hide()
	$Verre/Mesh.hide()


func _apply() -> void:
	if not is_inside_tree() or get_node_or_null("Mask/Face") == null:
		return
	var face := StandardMaterial3D.new()
	face.albedo_color = face_color
	face.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = accent_color
	for n in ["Mask/Face", "Mask/Nose"]:
		(get_node(n) as MeshInstance3D).material_override = face
	for n in ["Mask/Band", "Mask/CheekL", "Mask/CheekR"]:
		(get_node(n) as MeshInstance3D).material_override = accent
