class_name Levels
extends RefCounted
## Données des niveaux et des masques. Coordonnées en mètres : x = est, z = sud.
## walls : [centre_x, centre_z, largeur_x, largeur_z] (cloisons intérieures)
## vitrines : [x, z, rotation_deg, id_masque] ; columns : [x, z]
## entry / exit : [x, z, mur "N" | "S" | "E" | "W"] ; spawn : [x, z, orientation_deg]
## guards : wp = points de ronde, start = point de départ, spin = rotation sur place (rad/s)

const LEVELS := [
	{
		"name": "La Salle des Masques",
		"size": Vector2(20, 12),
		"walls": [],
		"columns": [],
		"rugs": [[0, 0, 16, 2.2]],
		"benches": [[-7, -4.6, 0], [7, 4.6, 0]],
		"entry": [-10, 0, "W"], "exit": [10, 0, "E"], "spawn": [-7.3, 0, -90],
		"vitrines": [[-4.5, -2.5, 0, "m1"], [-4.5, 2.5, 180, "m2"], [0, 0, 90, "m3"], [4.5, -2.5, 0, "m4"], [4.5, 2.5, 180, "m5"]],
		"guards": [{"wp": [[-2.2, -4.8], [2.2, -4.8], [2.2, 4.8], [-2.2, 4.8]]}],
	},
	{
		"name": "La Galerie en L",
		"size": Vector2(28, 20),
		"walls": [[-6, 0, 16, 0.4], [6, -4.5, 0.4, 11]],
		"columns": [[-6, -7.5], [-6, -2.5]],
		"rugs": [[-3, 5, 20, 2.2], [-5.5, -5, 14, 2.0], [10, 0, 2.2, 16]],
		"benches": [[-6, 8.6, 0], [3, -9, 0]],
		"entry": [-14, 5, "W"], "exit": [10, -10, "N"], "spawn": [-12.5, 5, -90],
		"vitrines": [[-10, -7.5, 0, "m6"], [-2, -7.5, 0, "m7"], [-10, -2.5, 180, "m8"], [-2, -2.5, 180, "m9"], [10.5, -6, 270, "m10"], [9.5, 6, 180, "m11"]],
		"guards": [
			{"wp": [[-12, -5], [1, -5]]},
			{"wp": [[10, 0]], "spin": 0.5},
		],
	},
	{
		"name": "Le Grand Hall",
		"size": Vector2(36, 24),
		"walls": [[-8, -6.6, 0.4, 10.8], [-8, 6.6, 0.4, 10.8], [8, -6.6, 0.4, 10.8], [8, 6.6, 0.4, 10.8]],
		"columns": [[-4, -6], [4, -6], [-4, 6], [4, 6]],
		"rugs": [[0, 0, 9, 13], [-12.5, 0, 2.2, 20], [12.5, 0, 2.2, 20], [0, 9, 2.2, 5]],
		"benches": [[0, 0, 90], [-10, -5, 90], [10, -5, 90]],
		"entry": [0, 12, "S"], "exit": [0, -12, "N"], "spawn": [0, 10.5, 0],
		"vitrines": [[-5, 0, 90, "m12"], [5, 0, 270, "m13"], [-15, -8, 90, "m1"], [-15, 8, 90, "m2"], [-11, 0, 90, "m3"], [15, -8, 270, "m4"], [11, 4, 270, "m5"]],
		"guards": [
			{"wp": [[-3, -3], [3, -3], [3, 3], [-3, 3]]},
			{"wp": [[-12.5, -10], [-12.5, 10]]},
			{"wp": [[12.5, -10], [12.5, 10]], "start": 1},
		],
	},
]

## id : [nom, matière, histoire, couleur visage, couleur motifs] — masques inventés pour le jeu.
const MASKS := {
	"m1": ["Le Gardien des Pluies", "Bois d'ébène sculpté, pigments de kaolin",
		"On raconte qu'il était porté une seule nuit par an, quand le village attendait la première pluie. Ses bandes blanches imitent les traces de l'eau sur la roche.",
		Color(0.35, 0.2, 0.1), Color(0.95, 0.9, 0.8)],
	"m2": ["La Dame de Lune", "Bois clair recouvert d'argile blanche",
		"Masque de la conteuse : celle qui le portait avait le droit de raconter les histoires interdites le jour. Son front rouge rappelle le soleil qui se couche avant le récit.",
		Color(0.85, 0.82, 0.75), Color(0.6, 0.15, 0.1)],
	"m3": ["Le Rieur du Marché", "Bois d'iroko, traits peints au charbon",
		"Porté pendant les grandes fêtes du marché, il se moquait des puissants sans que personne n'ait le droit de se fâcher. Il fallait rire en le voyant passer.",
		Color(0.6, 0.35, 0.12), Color(0.15, 0.1, 0.08)],
	"m4": ["Le Forgeron d'Or", "Bois noirci au feu, incrustations dorées",
		"Il appartenait à une famille de forgerons. Le doré représente le métal en fusion ; on disait qu'il protégeait les mains de celui qui travaillait le feu.",
		Color(0.2, 0.12, 0.08), Color(0.85, 0.65, 0.2)],
	"m5": ["L'Esprit de la Savane", "Bois rouge, motifs blancs à la chaux",
		"Masque des messagers : il accompagnait ceux qui partaient loin annoncer une naissance ou une alliance. Ses marques blanches sont les chemins à suivre.",
		Color(0.7, 0.25, 0.12), Color(0.95, 0.95, 0.9)],
	"m6": ["Le Veilleur du Fleuve", "Bois flotté poli, perles de verre bleu",
		"Taillé dans un tronc rapporté par la crue, il veillait sur les pêcheurs partis de nuit. Les perles bleues figurent les reflets de la lune sur l'eau.",
		Color(0.45, 0.4, 0.33), Color(0.2, 0.45, 0.8)],
	"m7": ["La Reine des Abeilles", "Bois de karité, cire et ocre jaune",
		"Les récolteurs de miel le saluaient avant de grimper aux arbres. On disait que l'odeur de cire du masque calmait les essaims.",
		Color(0.75, 0.55, 0.2), Color(0.25, 0.15, 0.05)],
	"m8": ["Le Sage aux Trois Yeux", "Bois dur, cauris incrustés",
		"Le troisième œil, sur le front, voyait ce que les deux autres ignoraient. Seul le plus ancien du conseil avait le droit de le regarder en face.",
		Color(0.3, 0.22, 0.15), Color(0.95, 0.92, 0.85)],
	"m9": ["Le Danseur de Feu", "Bois rouge laqué, fibres de raphia",
		"Il ouvrait la danse des moissons autour du grand feu. Ses lignes noires suivent les mouvements des flammes quand le danseur tournait sur lui-même.",
		Color(0.75, 0.2, 0.1), Color(0.1, 0.08, 0.05)],
	"m10": ["La Mère des Récoltes", "Bois clair, teinture d'indigo",
		"Offert à la famille qui avait nourri le village pendant une année de sécheresse. Les bandes indigo représentent les sillons des champs.",
		Color(0.8, 0.7, 0.55), Color(0.15, 0.2, 0.5)],
	"m11": ["Le Masque du Silence", "Ébène mat, bouche scellée de cuivre",
		"Porté par le juge pendant les palabres : sa bouche fermée rappelait que l'on doit écouter longtemps avant de parler.",
		Color(0.12, 0.1, 0.08), Color(0.75, 0.45, 0.25)],
	"m12": ["Le Chasseur d'Étoiles", "Bois sombre, clous de laiton",
		"Les voyageurs du désert s'en servaient pour apprendre aux enfants le nom des étoiles. Chaque clou de laiton correspond à une constellation.",
		Color(0.22, 0.18, 0.2), Color(0.95, 0.8, 0.35)],
	"m13": ["Le Roi Caméléon", "Bois peint de cinq couleurs",
		"On disait que ce masque changeait d'humeur selon la lumière. Le roi qui le portait devait savoir s'adapter à chacun de ses sujets.",
		Color(0.25, 0.5, 0.3), Color(0.9, 0.75, 0.2)],
}
