// The map's ground: hill shading and contours computed from the same heightmap
// the battle uses, so it stays sharp at any zoom. Contours every 5 m, index
// contours every 25 m.
shader_type canvas_item;

#include "res://shaders/terrain_inc.gdshaderinc"

uniform vec2 view_center = vec2(0.0); // world (x, z) at the centre of the control
uniform float px_per_m = 0.15;
uniform vec2 rect_size = vec2(1600.0, 900.0);

void fragment() {
	vec2 w = view_center + (UV - 0.5) * rect_size / px_per_m;
	float hs = terrain_size * 0.5;
	if (abs(w.x) > hs || abs(w.y) > hs) {
		COLOR = vec4(0.085, 0.075, 0.06, 1.0);
	} else {
		float h = terrain_h(w);
		float e = 12.0;
		float hx = terrain_h(w + vec2(e, 0.0)) - terrain_h(w - vec2(e, 0.0));
		float hz = terrain_h(w + vec2(0.0, e)) - terrain_h(w - vec2(0.0, e));
		float shade = clamp(0.82 - (hx + hz) * 0.06, 0.45, 1.05);
		float t = clamp((h + 20.0) / 60.0, 0.0, 1.0);
		vec3 c = mix(vec3(0.87, 0.83, 0.68), vec3(0.68, 0.6, 0.44), t) * shade;
		float k = h / 5.0;
		float minor = abs(fract(k + 0.5) - 0.5) / max(fwidth(k), 1e-4);
		float k2 = h / 25.0;
		float major = abs(fract(k2 + 0.5) - 0.5) / max(fwidth(k2), 1e-4);
		c = mix(c * 0.78, c, smoothstep(0.0, 1.0, minor));
		c = mix(c * 0.6, c, smoothstep(0.0, 1.5, major));
		COLOR = vec4(c, 1.0);
	}
}
