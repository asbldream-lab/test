shader_type spatial;
// Uniforme de gardien "peint" par zones de hauteur sur le mannequin
// (chaussures, pantalon, ceinture, chemise, peau du cou/tête et des mains).

uniform vec3 shirt : source_color = vec3(0.55, 0.66, 0.82);
uniform vec3 trousers : source_color = vec3(0.07, 0.09, 0.2);
uniform vec3 skin : source_color = vec3(0.52, 0.36, 0.25);
uniform vec3 dark : source_color = vec3(0.03, 0.03, 0.035);

varying float h;
varying float r;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = w.y - NODE_POSITION_WORLD.y;            // hauteur au-dessus des pieds
	r = length(w.xz - NODE_POSITION_WORLD.xz);  // distance à l'axe du corps
}

void fragment() {
	vec3 c = shirt;
	float rough = 0.8;
	if (h < 0.09) { c = dark; rough = 0.4; }            // chaussures
	else if (h < 0.95) { c = trousers; }                 // pantalon
	else if (h < 1.02) { c = dark; rough = 0.35; }       // ceinture
	else if (h > 1.5) { c = skin; rough = 0.6; }         // cou et tête
	if (r > 0.23 && h > 0.6 && h < 0.95) { c = skin; rough = 0.6; } // mains le long du corps
	ALBEDO = c;
	ROUGHNESS = rough;
}
