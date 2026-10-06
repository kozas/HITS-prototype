// The fallen: static instances, coat colour in INSTANCE_CUSTOM.
shader_type spatial;
render_mode cull_back;

varying vec3 v_color;

void vertex() {
	int mat_id = int(UV.x + 0.5);
	vec3 c = COLOR.rgb;
	if (mat_id == 1) {
		c = INSTANCE_CUSTOM.rgb;
	}
	v_color = c * 0.75;
	if (int(UV.y + 0.5) == 5) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.95;
}
