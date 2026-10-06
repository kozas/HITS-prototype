// Every soldier on the field is drawn by this shader. Soldiers have NO CPU state:
// position, facing, pose and animation are a pure function of
//   (formation instance uniforms, INSTANCE_ID = slot index, sim_time, seed).
// The layout functions below must mirror Formation.footprint_for() in formation.gd.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/terrain_inc.gdshaderinc"

uniform float sim_time = 0.0;

// x = formation type from, y = formation type to, z = transition start (sim s), w = duration
instance uniform vec4 form_state = vec4(1.0, 1.0, -1000.0, 0.0);
// x = strength, y = ranks when in line, z = seed, w = unused
instance uniform vec4 form_dims = vec4(600.0, 3.0, 0.0, 0.0);
// x = moving 0/1, y = last volley time, z = rout amount 0..1, w = cadence multiplier
instance uniform vec4 anim_state = vec4(0.0, -1000.0, 0.0, 1.0);
instance uniform vec4 coat_color = vec4(0.02, 0.03, 0.15, 1.0);
instance uniform vec4 trim_color = vec4(0.7, 0.7, 0.65, 1.0);
instance uniform vec4 trouser_color = vec4(0.7, 0.7, 0.65, 1.0);

const float FILE_W = 0.62;
const float RANK_D = 0.85;
const int COLUMN_FILES = 48;
const int MARCH_FILES = 6;
const vec3 MUZZLE = vec3(0.27, 2.2, -0.02);

varying vec3 v_color;
varying float v_part;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash_f(uint x) {
	return float(hash_u(x) & 16777215u) / 16777215.0;
}

// Each returns vec4(local x, local z, yaw, rank). Formation anchor = centre of
// the front rank; +z is toward the rear.
vec4 slot_line(int i, int n, int ranks) {
	int files = max((n + ranks - 1) / ranks, 1);
	int file = i / ranks;
	int rank = i % ranks;
	float x = (float(file) - float(files - 1) * 0.5) * FILE_W;
	return vec4(x, float(rank) * RANK_D, 0.0, float(rank));
}

vec4 slot_column(int i, int n) {
	int cf = max(min(n, COLUMN_FILES), 1);
	int row = i / cf;
	int file = i % cf;
	float x = (float(file) - float(cf - 1) * 0.5) * FILE_W;
	float z = float(row) * RANK_D + float(row / 3) * 2.4;
	return vec4(x, z, 0.0, float(row));
}

vec4 slot_march(int i, int n) {
	int row = i / MARCH_FILES;
	int file = i % MARCH_FILES;
	return vec4((float(file) - float(MARCH_FILES - 1) * 0.5) * 0.7, float(row) * 1.1, 0.0, float(row));
}

vec4 slot_square(int i, int n) {
	int per_face = (n + 3) / 4;
	int fpf = max((per_face + 3) / 4, 1);
	int face = i % 4;
	int j = i / 4;
	int rank = j % 4;
	int file = j / 4;
	float half_side = float(fpf) * FILE_W * 0.5 + 4.0 * RANK_D;
	vec2 p = vec2((float(file) - float(fpf - 1) * 0.5) * FILE_W, -half_side + float(rank) * RANK_D + 0.4);
	float a = float(face) * PI * 0.5;
	float c = cos(a);
	float s = sin(a);
	vec2 r = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	return vec4(r.x, r.y + half_side, a, float(rank));
}

vec4 slot_for(int type, int i, int n, int ranks) {
	if (type == 0) {
		return slot_line(i, n, ranks);
	} else if (type == 1) {
		return slot_column(i, n);
	} else if (type == 2) {
		return slot_square(i, n);
	}
	return slot_march(i, n);
}

vec2 rot2(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

vec3 rot_x(vec3 v, vec2 pivot, float a) {
	vec2 p = v.yz - pivot;
	v.yz = rot2(p, a) + pivot;
	return v;
}

void vertex() {
	int i = INSTANCE_ID;
	int n = int(form_dims.x + 0.5);
	int ranks = max(int(form_dims.y + 0.5), 1);
	uint seed = uint(form_dims.z) * 7919u + uint(i) * 2654435761u;
	float h1 = hash_f(seed);
	float h2 = hash_f(seed + 1u);
	float h3 = hash_f(seed + 2u);
	float h4 = hash_f(seed + 3u);

	// Formation change: each man walks from his old slot to his new one with a random delay.
	int fa = int(form_state.x + 0.5);
	int fb = int(form_state.y + 0.5);
	float tg = form_state.w > 0.0 ? clamp((sim_time - form_state.z) / form_state.w, 0.0, 1.0) : 1.0;
	float delay = h1 * 0.45;
	float tl = smoothstep(delay, delay + 0.55, tg);
	vec4 sa = slot_for(fa, i, n, ranks);
	vec4 sb = slot_for(fb, i, n, ranks);
	vec2 pos = mix(sa.xy, sb.xy, tl);
	float dyaw = mod(sb.z - sa.z + PI, TAU) - PI;
	float yaw = sa.z + dyaw * tl;
	float rank = tl < 0.5 ? sa.w : sb.w;
	float transit = (tl > 0.001 && tl < 0.999) ? 1.0 : 0.0;

	// Rout: scatter, turn about and run.
	float rout = anim_state.z;
	pos += (vec2(h2, h3) - 0.5) * 0.14;
	pos += (vec2(h3, h4) * 2.0 - 1.0) * vec2(22.0, 30.0) * rout;
	yaw = mix(yaw, PI + (h4 - 0.5) * 1.2, clamp(rout * 4.0, 0.0, 1.0));

	float moving = max(max(anim_state.x, transit), step(0.01, rout));
	float phase = sim_time * 4.0 * anim_state.w + h1 * 0.4 + rout * h2 * 6.28;
	float swing = sin(phase) * 0.45 * moving;
	float bob = abs(cos(phase)) * 0.035 * moving;

	// Volley: front two ranks present, then fire raggedly.
	float vt = anim_state.y;
	float fire_rank = step(rank, 1.5) * (1.0 - moving);
	float present = fire_rank * smoothstep(vt - 1.6, vt - 1.1, sim_time) * (1.0 - smoothstep(vt + 0.3, vt + 0.9, sim_time));
	float shot_t = vt + h2 * 0.35;
	float flash = fire_rank * step(shot_t, sim_time) * (1.0 - step(shot_t + 0.09, sim_time));

	int part = int(UV.y + 0.5);
	vec3 v = VERTEX;
	vec3 nrm = NORMAL;
	if (part == 1) {
		v = rot_x(v, UV2, swing);
	} else if (part == 2) {
		v = rot_x(v, UV2, -swing);
	} else if (part == 3) {
		v = rot_x(v, UV2, -1.42 * present);
		nrm = rot_x(nrm, vec2(0.0), -1.42 * present);
	} else if (part == 5) {
		v = MUZZLE + (v - MUZZLE) * flash * 1.6;
		v = rot_x(v, UV2, -1.42 * present);
	} else if (part == 4) {
		// Far tier card: turn to face the camera about the vertical axis.
		vec3 cam_local = transpose(mat3(MODEL_MATRIX)) * (INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec2 to_cam = cam_local.xz - pos;
		yaw = atan(-to_cam.x, to_cam.y);
	}
	v.y += bob;
	v *= 0.94 + h3 * 0.11;
	v.xz = rot2(v.xz, yaw);
	nrm.xz = rot2(nrm.xz, yaw);

	vec3 base = vec3(pos.x, 0.0, pos.y);
	vec3 wbase = (MODEL_MATRIX * vec4(base, 1.0)).xyz;
	base.y = terrain_h(wbase.xz) - MODEL_MATRIX[3].y;
	VERTEX = base + v;
	NORMAL = nrm;

	int mat_id = int(UV.x + 0.5);
	vec3 c = COLOR.rgb;
	if (mat_id == 1) {
		c = coat_color.rgb * (0.88 + h4 * 0.24);
	} else if (mat_id == 2) {
		c = trim_color.rgb;
	} else if (mat_id == 3) {
		c = trouser_color.rgb * (0.9 + h2 * 0.15);
	}
	v_color = c;
	v_part = float(part);
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	if (v_part > 4.5) {
		ALBEDO = vec3(1.0, 0.8, 0.4);
		EMISSION = vec3(1.0, 0.55, 0.15) * 24.0;
	}
}
