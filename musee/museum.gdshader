shader_type spatial;
// Matières procédurales du musée, en coordonnées monde (raccords parfaits entre dalles).
// mode : 0 parquet, 1 mur (lambris bois + tissu damassé + moulures dorées),
//        2 marbre, 3 tapis (UV d'un PlaneMesh), 4 plafond à caissons

uniform int mode = 0;
uniform vec3 color_a : source_color = vec3(0.3, 0.18, 0.1);
uniform vec3 color_b : source_color = vec3(0.5, 0.32, 0.18);
uniform vec3 color_c : source_color = vec3(0.78, 0.6, 0.28);
uniform vec2 rug_size = vec2(4.0, 2.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

// Lames de parquet décalées, teinte par lame, veinage, joints sombres.
vec4 parquet() {
	vec2 p = wpos.xz;
	float row = floor(p.y / 0.18);
	float x = p.x + hash(vec2(row, 3.0)) * 1.4;
	float col = floor(x / 1.4);
	vec2 l = vec2(fract(x / 1.4), fract(p.y / 0.18));
	float id = hash(vec2(col, row));
	float grain = fbm(vec2(x * 1.5, p.y * 45.0 + id * 17.0));
	vec3 c = mix(color_a, color_b, id * 0.6 + grain * 0.5);
	float seam = max(1.0 - smoothstep(0.0, 0.05, l.y), smoothstep(0.988, 1.0, l.x));
	c *= 1.0 - 0.5 * seam;
	return vec4(c, mix(0.25, 0.45, grain));
}

// Mur : lambris en bois en bas, moulures dorées, tissu damassé au-dessus.
vec4 wall(out float metal) {
	metal = 0.0;
	float y = wpos.y;
	float u = wpos.x + wpos.z;
	if (y < 1.1) {
		vec2 q = vec2(fract(u / 1.2), (y - 0.18) / 0.82);
		float frame = max(max(step(q.x, 0.06), step(0.94, q.x)), max(step(q.y, 0.1), step(0.9, q.y)));
		float g = fbm(vec2(u * 2.5, y * 30.0));
		vec3 c = mix(vec3(0.13, 0.07, 0.04), vec3(0.24, 0.14, 0.08), g);
		c *= mix(1.0, 0.7, frame);
		if (y < 0.18) c = vec3(0.06, 0.035, 0.02);
		return vec4(c, 0.4);
	}
	if (y < 1.17 || y > 3.78) {
		metal = 0.8;
		return vec4(color_c * (0.8 + 0.2 * noise(vec2(u * 20.0, y * 20.0))), 0.35);
	}
	vec2 p = vec2(u, y) * 2.2;
	vec2 cell = fract(p) - 0.5;
	float d = abs(cell.x) + abs(cell.y);
	float motif = smoothstep(0.34, 0.3, d) - smoothstep(0.24, 0.2, d) + smoothstep(0.09, 0.05, length(cell));
	float fab = fbm(p * 14.0);
	vec3 c = color_a * (0.8 + 0.3 * fab);
	c = mix(c, color_b, clamp(motif, 0.0, 1.0) * 0.55);
	return vec4(c, 0.9 - 0.35 * motif);
}

// Marbre blanc veiné.
vec4 marble() {
	vec2 p = vec2(wpos.x + wpos.z, wpos.y) * 1.4;
	float n = fbm(p * 1.3);
	float v = abs(sin(p.x * 2.0 + p.y * 1.3 + n * 7.0));
	vec3 c = mix(color_b, color_a, smoothstep(0.0, 0.18, v));
	c *= 0.92 + 0.08 * fbm(p * 9.0);
	return vec4(c, 0.15);
}

// Tapis : bordure dorée, filet, losanges ; laine.
vec4 rug(vec2 uv) {
	vec2 m = min(uv, 1.0 - uv) * rug_size;
	float e = min(m.x, m.y);
	vec3 c = color_a;
	if (e < 0.07) c = color_c * 0.7;
	else if (e < 0.11) c = color_a * 0.55;
	else if (e < 0.24) c = mix(color_c, color_a, 0.45 + 0.3 * step(0.5, fract((uv.x * rug_size.x + uv.y * rug_size.y) * 3.0)));
	else {
		vec2 cell = fract(uv * rug_size * 1.6) - 0.5;
		float d = abs(cell.x) + abs(cell.y);
		c = mix(color_a, color_b, smoothstep(0.42, 0.38, d) - smoothstep(0.3, 0.26, d) + smoothstep(0.08, 0.05, d));
	}
	c *= 0.85 + 0.3 * fbm(uv * rug_size * 35.0);
	return vec4(c, 1.0);
}

// Plafond à caissons.
vec4 ceiling() {
	vec2 q = fract(wpos.xz / 2.5);
	float beam = max(max(step(q.x, 0.06), step(0.94, q.x)), max(step(q.y, 0.06), step(0.94, q.y)));
	vec3 c = mix(color_a, color_b, beam) * (0.9 + 0.1 * fbm(wpos.xz * 3.0));
	return vec4(c, 0.9);
}

void fragment() {
	vec4 r;
	float metal = 0.0;
	if (mode == 0) r = parquet();
	else if (mode == 1) r = wall(metal);
	else if (mode == 2) r = marble();
	else if (mode == 3) r = rug(UV);
	else r = ceiling();
	ALBEDO = r.rgb;
	ROUGHNESS = r.a;
	METALLIC = metal;
	SPECULAR = 0.5;
}
