// Battalion colours. Flags are visible far past the men, which makes them
// the main way a general reads the field at range.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/terrain_inc.gdshaderinc"

instance uniform float flag_style = 0.0;

varying vec2 v_uv;
varying float v_cloth;
varying vec3 v_color;

void vertex() {
	vec3 w = MODEL_MATRIX[3].xyz;
	vec3 v = VERTEX;
	if (UV2.x > 0.5) {
		float fx = UV.x;
		v.z += sin(fx * 5.0 - TIME * 3.5 + w.x * 0.1) * 0.14 * fx;
		v.y += sin(fx * 3.0 - TIME * 2.1) * 0.05 * fx;
	}
	v.y += terrain_h(w.xz) - w.y;
	VERTEX = v;
	v_uv = UV;
	v_cloth = UV2.x;
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 c = v_color;
	if (v_cloth > 0.5) {
		vec3 blue = vec3(0.01, 0.03, 0.25);
		vec3 white = vec3(0.85);
		vec3 red = vec3(0.6, 0.02, 0.02);
		if (flag_style < 0.5) {
			c = v_uv.x < 0.333 ? blue : (v_uv.x < 0.666 ? white : red);
		} else {
			vec2 p = abs(v_uv - 0.5);
			float diag = abs(p.x - p.y);
			c = (p.x < 0.06 || p.y < 0.08) ? red : ((p.x < 0.11 || p.y < 0.14 || diag < 0.05) ? white : blue);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
