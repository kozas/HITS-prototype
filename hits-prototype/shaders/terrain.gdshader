shader_type spatial;
render_mode cull_back;

#include "res://shaders/terrain_inc.gdshaderinc"

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float grid_spacing = 12.0;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = terrain_h(w.xz);
	VERTEX.y = h;
	float e = grid_spacing;
	float hl = terrain_h(w.xz - vec2(e, 0.0));
	float hr = terrain_h(w.xz + vec2(e, 0.0));
	float hd = terrain_h(w.xz - vec2(0.0, e));
	float hu = terrain_h(w.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	wpos = vec3(w.x, h, w.z);
}

void fragment() {
	vec2 p = wpos.xz;
	// Patchwork of fields gives the eye a sense of scale at range. Domain-warped
	// strips of varying length so it doesn't read as a grid.
	vec2 warp = vec2(texture(detail_noise, p * 0.0005).r, texture(detail_noise, p * 0.0005 + vec2(0.37, 0.71)).r) - 0.5;
	vec2 q = vec2(p.x * 0.96 + p.y * 0.28, -p.x * 0.28 + p.y * 0.96) + warp * 70.0;
	float row = floor(q.y / 150.0);
	float strip = 140.0 + 260.0 * hash12(vec2(row, 7.0));
	q.x += hash12(vec2(row, 3.0)) * strip;
	vec2 fsize = vec2(strip, 150.0);
	vec2 cell = vec2(floor(q.x / strip), row);
	float r = hash12(cell);
	vec3 meadow = vec3(0.23, 0.33, 0.11);
	vec3 wheat = vec3(0.50, 0.45, 0.22);
	vec3 rye = vec3(0.38, 0.41, 0.18);
	vec3 pasture = vec3(0.29, 0.37, 0.14);
	vec3 plough = vec3(0.31, 0.25, 0.16);
	vec3 col = r < 0.3 ? meadow : (r < 0.5 ? wheat : (r < 0.7 ? rye : (r < 0.88 ? pasture : plough)));
	float n1 = texture(detail_noise, p * 0.0021).r;
	float n2 = texture(detail_noise, p * 0.031).r;
	float n3 = texture(detail_noise, p * 0.41).r;
	col *= 0.78 + 0.35 * n1;
	col *= 0.88 + 0.22 * n2;
	col *= 0.9 + 0.2 * n3;
	vec2 f = fract(q / fsize) * fsize;
	float edge = min(min(f.x, fsize.x - f.x), min(f.y, fsize.y - f.y));
	float aa = fwidth(edge);
	col = mix(col * vec3(0.55, 0.7, 0.5), col, smoothstep(1.0, 2.5 + aa, edge));
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
