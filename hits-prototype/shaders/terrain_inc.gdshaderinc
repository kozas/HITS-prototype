// Shared heightmap sampling. The terrain mesh, every soldier, flag and ribbon,
// and the CPU sampler in terrain.gd all use this exact mapping, so men stand
// on the ground the player sees.
uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float hm_res = 512.0;
uniform float terrain_size = 6132.0;

vec2 terrain_uv(vec2 xz) {
	vec2 t = (xz + vec2(terrain_size * 0.5)) / terrain_size;
	return (t * (hm_res - 1.0) + vec2(0.5)) / hm_res;
}

float terrain_h(vec2 xz) {
	return textureLod(heightmap, terrain_uv(xz), 0.0).r;
}
