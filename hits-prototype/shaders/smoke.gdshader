// Stateless smoke: each puff is written once (origin + spawn time in
// INSTANCE_CUSTOM). Drift, growth and fade are computed here from its age,
// so the CPU never touches a live puff.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float sim_time = 0.0;
uniform vec2 wind = vec2(0.9, 0.35);
uniform float brightness = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_alpha;
varying vec3 v_tint;
varying float v_seed;

void vertex() {
	// x = spawn time, y = size scale, z = seed, w = kind (0 musket smoke, 1 dust)
	vec4 cd = INSTANCE_CUSTOM;
	float age = sim_time - cd.x;
	float dust = step(0.5, cd.w);
	float life = mix(75.0, 30.0, dust);
	float k = clamp(age / life, 0.0, 1.0);
	float alive = step(0.0, age) * step(age, life);
	float size = mix(2.0, mix(26.0, 18.0, dust), sqrt(k)) * cd.y * alive;
	vec3 drift = vec3(wind.x, 0.0, wind.y) * age + vec3(0.0, 0.4 + age * 0.06, 0.0);
	vec3 offs = (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	VERTEX = drift + offs + vec3(0.0, size * 0.3, 0.0);
	v_alpha = mix(0.42, 0.22, dust) * smoothstep(0.0, 0.5, age) * (1.0 - k) * (1.0 - k);
	v_tint = mix(vec3(0.82, 0.82, 0.8), vec3(0.5, 0.43, 0.33), dust);
	v_seed = cd.z;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float n = texture(noise_tex, UV * 0.6 + vec2(v_seed * 7.0, v_seed * 3.0)).r;
	float d = length(uv) * 2.0 + (n - 0.5) * 0.6;
	float a = smoothstep(1.0, 0.2, d) * v_alpha;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -vp.z / vp.w;
	float frag_z = -VERTEX.z;
	a *= clamp((scene_z - frag_z) / 3.0, 0.0, 1.0);
	a *= smoothstep(0.5, 5.0, frag_z);
	ALBEDO = v_tint * (0.75 + 0.35 * n) * brightness;
	ALPHA = a;
}
