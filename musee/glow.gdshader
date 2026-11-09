shader_type spatial;
// Lumière "douce" additive : cône de vision au sol (mode 0) et faisceau de lampe (mode 1).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float strength = 0.25;
uniform float beam_length = 5.0;

varying float along;

void vertex() {
	along = 0.5 - VERTEX.y / beam_length; // faisceau : 0 à la lampe, 1 au bout
}

void fragment() {
	float a;
	if (mode == 0) {
		// UV.x = distance (0 au gardien, 1 au bout), UV.y = position dans l'angle (0..1)
		a = pow(1.0 - UV.x, 1.6) * pow(sin(UV.y * 3.14159), 1.5);
	} else {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a = pow(1.0 - clamp(along, 0.0, 1.0), 2.0) * pow(facing, 2.5);
	}
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
