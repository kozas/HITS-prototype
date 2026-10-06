// Furthest tier: a whole battalion as one terrain-conforming box with a
// procedural "rank" pattern that fades to its average colour when files get
// smaller than a pixel (no shimmer).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/terrain_inc.gdshaderinc"

// x = width (m), y = depth (m)
instance uniform vec4 ribbon_dims = vec4(120.0, 3.0, 0.0, 0.0);
instance uniform vec4 coat_color = vec4(0.02, 0.03, 0.15, 1.0);
instance uniform vec4 trim_color = vec4(0.7, 0.7, 0.65, 1.0);
instance uniform vec4 trouser_color = vec4(0.7, 0.7, 0.65, 1.0);

varying vec3 v_local;

void vertex() {
	vec3 p = vec3(VERTEX.x * ribbon_dims.x, VERTEX.y * 1.8, VERTEX.z * ribbon_dims.y);
	vec3 w = (MODEL_MATRIX * vec4(p.x, 0.0, p.z, 1.0)).xyz;
	p.y += terrain_h(w.xz) - MODEL_MATRIX[3].y;
	v_local = vec3(p.x, VERTEX.y, p.z);
	VERTEX = p;
}

void fragment() {
	float along = v_local.x + v_local.z * 0.37;
	float file = floor(along / 0.62);
	float hsh = fract(sin(file * 12.9898) * 43758.5453);
	float y = v_local.y + (hsh - 0.5) * 0.05;
	vec3 shako = vec3(0.01);
	vec3 band = y > 0.84 ? shako : (y > 0.48 ? coat_color.rgb : trouser_color.rgb);
	float fx = abs(fract(along / 0.62) - 0.5);
	vec3 c = band;
	if (y > 0.55 && y < 0.8 && fx < 0.1) {
		c = trim_color.rgb;
	}
	c *= mix(0.55, 1.0, smoothstep(0.38, 0.3, fx));
	vec3 avg = band * 0.9;
	float aa = clamp(fwidth(along) / 0.62 * 1.5, 0.0, 1.0);
	ALBEDO = mix(c, avg, aa);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
