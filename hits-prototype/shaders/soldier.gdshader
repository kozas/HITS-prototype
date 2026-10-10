// Every man on the field (rank and file, officers, NCOs, drummers, colour guard)
// is drawn by this shader. None of them has CPU state: position, facing, pose and
// animation are a pure function of
//   (battalion instance uniforms, INSTANCE_ID, sim_time, seed).
//
// Organisation (French 1791 drill): a battalion is C companies, voltigeurs on the
// left, grenadiers on the right. Each company is two sections (2nd on the left,
// 1st on the right) with its captain in the front rank on the right, and its
// lieutenant and sergeants 2 paces behind the rear rank.
//
// Formations place *sections* as rigid blocks; drill moves those blocks. On the
// word of command each block faces the way it must go, marches there at the quick
// step and fronts, so companies visibly ploy into column, wheel out into square
// and so on, rather than men shuffling individually.
//
// The geometry must mirror Formation.footprint_for() / colour_pos() in formation.gd.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/terrain_inc.gdshaderinc"

uniform float sim_time = 0.0;
// false: rank and file (INSTANCE_ID = man). true: officers, NCOs, drummers and
// colour guard (INSTANCE_ID = staff slot, see staff_pos()).
uniform bool staff = false;

// x = formation from, y = formation to, z = time the order was given (sim s),
// w = companies away (bit k: company k detached as skirmishers, not drawn here)
instance uniform vec4 form_state = vec4(1.0, 1.0, -1000.0, 0.0);
// x = strength, y = ranks, z = seed, w = companies
instance uniform vec4 form_dims = vec4(600.0, 3.0, 0.0, 6.0);
// x = moving 0/1, y = last volley time, w = cadence multiplier,
// z = rout clock: 0 steady, routing since z - 1 if z > 0, rallying since -z - 1 if z < 0
instance uniform vec4 anim_state = vec4(0.0, -1000.0, 0.0, 1.0);
// x = time the battalion last started or stopped marching,
// y = fire (0 volley, 1 by platoon, 2 at will), z = continuous fire began, w = ended
instance uniform vec4 drill_state = vec4(-1000.0, 0.0, -1000.0, -1000.0);
instance uniform vec4 coat_color = vec4(0.02, 0.03, 0.15, 1.0);
instance uniform vec4 trim_color = vec4(0.7, 0.7, 0.65, 1.0);
instance uniform vec4 trouser_color = vec4(0.7, 0.7, 0.65, 1.0);

const int LINE = 0;
const int COLUMN = 1;
const int SQUARE = 2;
const int MARCH = 3;
const int OPEN = 4;  // skirmish order: a light company out on its own

const float FILE_W = 0.6;    // elbow to elbow
const float RANK_D = 0.65;   // 0.325 m between ranks, plus the man
const float SERRE = 1.3;     // officers and sergeants 2 paces behind the rear rank
const float GUARD_W = 1.2;   // colour guard: 2 files in the centre of the battalion
const float QUICK = 1.08;    // pas accéléré: 100 paces/min of 0.65 m
const float FACE_T = 0.8;    // time to face left, right or about
const vec3 MUZZLE = vec3(0.27, 2.2, -0.02);
// Mirrors of Formation.ROUT_SCATTER_T, RALLY_REFORM_T, PLATOON_CYCLE, AT_WILL_CYCLE.
const float ROUT_T = 8.0;
const float RALLY_T = 15.0;
const float PLATOON_CYCLE = 20.0;
const float AT_WILL_CYCLE = 16.0;
// Open order (mirrors Formation.SKIRMISH_GAP, SUPPORT_DIST, OPEN_FORM_T): pairs
// this far apart, a quarter of the company in support this far behind.
const float SKIRMISH_GAP = 4.0;
const float SUPPORT_DIST = 40.0;
const float OPEN_FORM_T = 12.0;

// Mesh parts (UV.y), see meshes.gd
const int P_LEG_L = 1;
const int P_LEG_R = 2;
const int P_MUSKET = 3;
const int P_CARD = 4;
const int P_FLASH = 5;
const int P_HORSE_FORE = 9;
const int P_HORSE_HIND = 10;
const int P_HORSE_FIRST = 8;

// Staff roles -> visible parts (bit per part)
const int BODY = (1 << 0) | (1 << 1) | (1 << 2);
const int MASK_NCO = BODY | (1 << 3) | (1 << 5) | (1 << 12) | (1 << 13);
const int MASK_OFFICER = BODY | (1 << 6) | (1 << 11) | (1 << 14);
const int MASK_DRUMMER = BODY | (1 << 7) | (1 << 12) | (1 << 13);
const int MASK_MOUNTED = BODY | (1 << 6) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 14);

varying vec3 v_color;
varying float v_part;

struct Bn {
	int n;       // men laid out
	int r;       // ranks
	int c;       // companies
	int pc;      // men per company
	int nf;      // files per company
	int hl;      // files in the 2nd (left) section
	float wc;    // company frontage, including the captain's file
	float wl;    // 2nd section frontage
	float wr;    // 1st section frontage
	float ddiv;  // depth of a company: ranks plus the line of officers
	float step;  // column of attack: half a company's frontage between divisions
	float step_s;// open column of sections: full distance
};

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

vec2 rot2(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

vec3 rot_x(vec3 v, vec2 pivot, float a) {
	v.yz = rot2(v.yz - pivot, a) + pivot;
	return v;
}

float mix_angle(float a, float b, float t) {
	return a + (mod(b - a + PI, TAU) - PI) * t;
}

Bn bn_make(int n, int r, int c) {
	Bn b;
	b.n = n;
	b.r = max(r, 1);
	b.c = max(c, 2);
	b.pc = max((n + b.c - 1) / b.c, 1);
	b.nf = max((b.pc + b.r - 1) / b.r, 1);
	b.hl = b.nf / 2;
	b.wc = float(b.nf + 1) * FILE_W;
	b.wl = float(b.hl) * FILE_W;
	b.wr = float(b.nf - b.hl) * FILE_W;
	b.ddiv = float(b.r) * RANK_D + SERRE;
	b.step = max(0.5 * b.wc, b.ddiv + 2.0);
	b.step_s = max(b.wr, b.ddiv + 3.0);
	return b;
}

// Battalion frontage and depth. The anchor is the centre of the front rank.
vec2 bn_size(Bn b, int type) {
	if (type == LINE) {
		return vec2(float(b.c) * b.wc + GUARD_W, b.ddiv);
	} else if (type == COLUMN) {
		return vec2(2.0 * b.wc + GUARD_W, float(b.c / 2 - 1) * b.step + b.ddiv);
	} else if (type == SQUARE) {
		return vec2(2.0 * b.wc, 2.0 * float(b.r) * RANK_D + float(max(b.c / 2 - 2, 0)) * b.wc);
	} else if (type == OPEN) {
		int pairs = (b.n - b.n / 4 + 1) / 2;
		return vec2(max(float(pairs) * SKIRMISH_GAP, 4.0), SUPPORT_DIST + 2.0 * RANK_D);
	}
	return vec2(b.wr, float(2 * b.c - 1) * b.step_s + b.ddiv);
}

// Man i in open order: (x, z, yaw, rank). The chain is pairs of men a few paces
// apart, each pair loosely placed (they take cover where they find it); the
// last quarter of the company stands in support, in two ranks, behind.
vec4 open_pos(Bn b, int i, float ha, float hb) {
	int support = b.n / 4;
	int chain = b.n - support;
	if (i < chain) {
		int pairs = (chain + 1) / 2;
		int q = i / 2;
		float partner = float(i % 2);
		float x = (float(q) - 0.5 * float(pairs - 1)) * SKIRMISH_GAP + (ha - 0.5) * 2.4 + partner * 0.9;
		float z = (hb - 0.5) * 3.0 + partner * 0.5;
		return vec4(x, z, (ha - 0.5) * 0.7, 0.0);
	}
	int j = i - chain;
	int files = max((support + 1) / 2, 1);
	return vec4((float(j / 2) - 0.5 * float(files - 1)) * FILE_W, SUPPORT_DIST + float(j % 2) * RANK_D, 0.0, 2.0);
}

// Company k: front-centre (x, z) and facing, for line, column and square.
vec3 company_frame(Bn b, int type, int k) {
	int half_c = b.c / 2;
	if (type == LINE) {
		float x = -0.5 * (float(b.c) * b.wc + GUARD_W) + (float(k) + 0.5) * b.wc + (k >= half_c ? GUARD_W : 0.0);
		return vec3(x, 0.0, 0.0);
	}
	// Column by division formed on the centre: the two centre companies (with the
	// colours between them) lead, the flank companies are last.
	float side = k < half_c ? -1.0 : 1.0;
	int d = k < half_c ? half_c - 1 - k : k - half_c;
	if (type == COLUMN) {
		return vec3(side * 0.5 * (GUARD_W + b.wc), float(d) * b.step, 0.0);
	}
	// (In square the colour guard goes inside, so the faces close up.)
	float x = side * 0.5 * b.wc;
	if (d == 0) {
		return vec3(x, 0.0, 0.0);
	}
	// Square from the column: the leading division faces out, the rear division
	// faces about and the companies between wheel outward to make the sides.
	float rd = float(b.r) * RANK_D;
	if (d == half_c - 1) {
		return vec3(x, 2.0 * rd + float(half_c - 2) * b.wc, PI);
	}
	return vec3(side * b.wc, rd + (float(d - 1) + 0.5) * b.wc, side * 0.5 * PI);
}

// Section s of company k (0 = 2nd/left, 1 = 1st/right): front-centre and facing.
vec3 section_frame(Bn b, int type, int k, int s) {
	if (type == MARCH) {
		// Open column of sections at full distance, right in front: grenadiers lead.
		int q = (b.c - 1 - k) * 2 + (1 - s);
		return vec3(0.0, float(q) * b.step_s, 0.0);
	}
	vec3 cf = company_frame(b, type, k);
	float lx = s == 0 ? -0.5 * b.wc + 0.5 * b.wl : -0.5 * b.wc + b.wl + 0.5 * b.wr;
	return vec3(cf.xy + rot2(vec2(lx, 0.0), cf.z), cf.z);
}

vec3 in_frame(vec3 f, vec2 local) {
	return vec3(f.xy + rot2(local, f.z), f.z);
}

// Staff slot i: 5 per company (captain, left guide, lieutenant, sergeant,
// drummer), then the battalion staff (chef de bataillon, adjutant-major,
// sous-adjutant-major, 2 guides généraux, caporal d'encadrement, 6 colour guard).
int staff_role(Bn b, int i) {
	if (i < 5 * b.c) {
		int r = i % 5;
		return r == 4 ? 2 : (r == 0 || r == 2 ? 1 : 0);
	}
	int s = i - 5 * b.c;
	return s == 0 ? 3 : (s <= 2 ? 1 : 0);
}

vec3 staff_pos(Bn b, int type, int i, float adv) {
	vec2 sz = bn_size(b, type);
	float w = sz.x;
	float d = sz.y;
	if (type == OPEN) {
		// Officers and sergeants along the chain, the bugler with the support.
		int k = i / 5;
		int r = i % 5;
		float x = (float(k) - 0.5 * float(b.c - 1)) * 0.5 * w;
		vec2 at = r == 0 ? vec2(x, 6.0) : (r == 4 ? vec2(x + 2.0, SUPPORT_DIST + 2.0)
			: (r == 2 ? vec2(x, SUPPORT_DIST - 2.5) : vec2(x + (r == 1 ? -0.2 : 0.2) * w, 3.0)));
		return vec3(at, 0.0);
	}
	float back = float(b.r - 1) * RANK_D + SERRE;
	if (i < 5 * b.c) {
		int k = i / 5;
		int r = i % 5;
		if (r == 4) {
			// Drummers are drawn from the companies into one band.
			int cols = max(b.c / 2, 1);
			vec2 o = vec2((float(k % cols) - 0.5 * float(cols - 1)) * 0.9, float(k / cols) * 0.9);
			vec2 base = type == LINE ? vec2(0.0, b.ddiv + 8.0)
				: (type == COLUMN ? vec2(0.0, d + 3.0) : (type == SQUARE ? vec2(0.0, 0.5 * d + 2.0) : vec2(0.0, -7.0)));
			return vec3(base + o, 0.0);
		}
		if (type == MARCH) {
			// Captain on the right of his leading section, sergeants on the flank.
			vec3 f1 = section_frame(b, MARCH, k, 1);
			vec3 f0 = section_frame(b, MARCH, k, 0);
			if (r == 0) {
				return vec3(0.5 * b.wr + 0.6, f1.y, 0.0);
			}
			return vec3(-0.5 * b.wr - 0.8, (r == 1 ? f1.y : f0.y) + (r == 3 ? 1.3 : 0.0), 0.0);
		}
		vec3 cf = company_frame(b, type, k);
		vec2 l = vec2(0.5 * b.wc - 0.5 * FILE_W, 0.0);
		if (r == 0 && type == SQUARE) {
			l = vec2(0.3 * b.wc, back + 1.0);
		} else if (r > 0) {
			l = vec2(r == 1 ? -0.5 * b.wc + 0.3 : (r == 2 ? -0.1 * b.wc : 0.25 * b.wc), back);
		}
		return in_frame(cf, l);
	}
	int s = i - 5 * b.c;
	float side = s == 3 ? -1.0 : 1.0;
	if (type == SQUARE) {
		// Everyone not in the ranks goes inside the square.
		vec2 inside = s == 0 ? vec2(3.0, -2.0) : (s <= 2 ? vec2(s == 1 ? -5.0 : 5.0, 0.0)
			: (s <= 4 ? vec2(side * 2.5, 4.0) : (s == 5 ? vec2(-1.5, 4.0) : vec2(0.0, -1.0))));
		if (s >= 6) {
			inside += vec2((float((s - 6) / 3) - 0.5) * FILE_W, float((s - 6) % 3) * RANK_D);
		}
		return vec3(inside + vec2(0.0, 0.5 * d), 0.0);
	}
	if (s == 0) {
		// Chef de bataillon, mounted: behind the centre of a line, beside a column.
		return type == LINE ? vec3(0.0, d + 14.0, 0.0) : (type == COLUMN ? vec3(0.5 * w + 9.0, 0.4 * d, 0.0) : vec3(5.0, 4.0, 0.0));
	}
	if (s <= 2) {
		float sx = s == 1 ? -1.0 : 1.0;
		return type == LINE ? vec3(sx * 0.25 * w, d + 4.0, 0.0) : vec3(sx * (0.5 * w + 3.0), 0.5 * d, 0.0);
	}
	if (s <= 4) {
		// Guides généraux: 4 paces behind the rear rank at the halt, 6 paces in
		// front of the line once it advances.
		float halted = type == LINE ? back + 2.6 : 0.5;
		return vec3(side * (0.5 * w + (type == LINE ? 0.0 : 0.8)), mix(halted, -3.9, adv), 0.0);
	}
	if (s == 5) {
		return vec3(-0.5 * w - 0.7, type == MARCH ? 3.0 : 0.0, 0.0);
	}
	// Colour guard: 2 files x 3 ranks round the colours, in the centre of the line
	// and between the companies of the leading division.
	int g = s - 6;
	vec2 base = type == MARCH ? vec2(0.0, 2.0 * b.step_s - 2.5) : vec2(0.0);
	return vec3(base + vec2((float(g / 3) - 0.5) * FILE_W, float(g % 3) * RANK_D), 0.0);
}

// Moves one block (section or single figure) from frame fa to frame fb.
// Returns (x, z, man yaw, marching 0/1).
vec4 drill(vec3 fa, vec3 fb, vec2 local, float t0, float width) {
	vec2 dp = fb.xy - fa.xy;
	float dist = length(dp);
	float dyaw = mod(fb.z - fa.z + PI, TAU) - PI;
	float march_t = (dist + abs(dyaw) * width * 0.5) / QUICK;
	float t = sim_time - t0;
	if (march_t < 0.05) {
		vec3 f = t < 0.0 ? fa : fb;
		return vec4(f.xy + rot2(local, f.z), f.z, 0.0);
	}
	float face = dist > 0.5 ? FACE_T : 0.0;
	float k = clamp((t - face) / march_t, 0.0, 1.0);
	float by = fa.z + dyaw * k;
	vec2 p = mix(fa.xy, fb.xy, k) + rot2(local, by);
	float yaw = by;
	if (face > 0.0) {
		// Face towards the new position (by the flank), march, then front.
		float travel = atan(dp.x, -dp.y);
		yaw = mix_angle(mix_angle(fa.z, travel, smoothstep(0.0, face, t)), fb.z, smoothstep(face + march_t, 2.0 * face + march_t, t));
	}
	return vec4(p, yaw, (t > 0.0 && t < 2.0 * face + march_t) ? 1.0 : 0.0);
}

void vertex() {
	int i = INSTANCE_ID;
	Bn b = bn_make(int(form_dims.x + 0.5), int(form_dims.y + 0.5), int(form_dims.w + 0.5));
	int fa = int(form_state.x + 0.5);
	int fb = int(form_state.y + 0.5);
	uint seed = uint(form_dims.z) * 7919u + uint(i) * 2654435761u + (staff ? 104729u : 0u);
	float h1 = hash_f(seed);
	float h2 = hash_f(seed + 1u);
	float h3 = hash_f(seed + 2u);
	float h4 = hash_f(seed + 3u);

	vec4 pose;
	float rank = 0.0;
	int mask = -1;
	int role = -1;
	int k = -1;
	if (!staff) {
		k = i / b.pc;
		int j = i % b.pc;
		int f = j / b.r;
		int s = f < b.hl ? 0 : 1;
		int cnt = s == 0 ? b.hl : b.nf - b.hl;
		rank = float(j % b.r);
		vec2 local = vec2((float(f - s * b.hl) + 0.5 - 0.5 * float(cnt)) * FILE_W, rank * RANK_D);
		if (fb == OPEN) {
			// Skirmishers: each man runs out to his place in the chain.
			vec4 op = open_pos(b, i, h1, h4);
			rank = op.w;
			if (fa == OPEN) {
				pose = vec4(op.xy, op.z, 0.0);
			} else {
				vec3 cp = in_frame(section_frame(b, fa, k, s), local);
				float t = sim_time - form_state.z - h2 * 1.5;
				float kk = smoothstep(0.0, OPEN_FORM_T - 1.5, t);
				pose = vec4(mix(cp.xy, op.xy, kk), mix(cp.z, op.z, kk), (t > 0.0 && kk < 1.0) ? 1.0 : 0.0);
			}
		} else {
			vec3 sb = section_frame(b, fb, k, s);
			if (fa == fb) {
				// Settled (the common case): one formation, no drill.
				pose = vec4(in_frame(sb, local), 0.0);
			} else {
				float t0 = form_state.z + 1.0 + hash_f(uint(form_dims.z) * 31u + uint(k) * 977u) * 0.8;
				pose = drill(section_frame(b, fa, k, s), sb, local, t0, float(cnt) * FILE_W);
			}
		}
	} else {
		float since = clamp((sim_time - drill_state.x) / 4.0, 0.0, 1.0);
		float adv = anim_state.x > 0.5 ? smoothstep(0.0, 1.0, since) : 1.0 - smoothstep(0.0, 1.0, since);
		role = staff_role(b, i);
		mask = role == 0 ? MASK_NCO : (role == 1 ? MASK_OFFICER : (role == 2 ? MASK_DRUMMER : MASK_MOUNTED));
		vec3 sb = staff_pos(b, fb, i, adv);
		if (fa == fb) {
			pose = vec4(sb, 0.0);
		} else {
			float t0 = form_state.z + 1.0 + (i < 5 * b.c ? hash_f(uint(form_dims.z) * 31u + uint(i / 5) * 977u) * 0.8 : 0.0);
			pose = drill(staff_pos(b, fa, i, adv), sb, vec2(0.0), t0, 0.0);
		}
	}
	vec2 pos = pose.xy;
	float yaw = pose.z;
	float transit = pose.w;

	// Rout: scatter, turn about and run; rallying, close up again.
	float rz = anim_state.z;
	float rout = rz > 0.0 ? clamp((sim_time - (rz - 1.0)) / ROUT_T, 0.0, 1.0)
		: (rz < 0.0 ? clamp(1.0 - (sim_time - (-rz - 1.0)) / RALLY_T, 0.0, 1.0) : 0.0);
	pos += (vec2(h2, h3) - 0.5) * 0.12;
	pos += (vec2(h3, h4) * 2.0 - 1.0) * vec2(22.0, 30.0) * rout;
	yaw = mix(yaw, PI + (h4 - 0.5) * 1.2, clamp(rout * 4.0, 0.0, 1.0));

	float moving = max(max(anim_state.x, transit), step(0.01, rout));
	float cadence = transit > 0.5 ? QUICK / 0.82 : anim_state.w;
	float phase = sim_time * 4.0 * cadence + h1 * 0.4 + rout * h2 * 6.28;
	float swing = sin(phase) * 0.45 * moving;
	float bob = abs(cos(phase)) * 0.035 * moving;

	// Fire: the front two ranks present, fire and recover. Volley: everyone at
	// the word, raggedly. By platoon: company after company from the right, the
	// same schedule as BattleSim.continuous_fire. At will: each man on his own
	// reloading cycle. vt is the shot this man is presenting for or has just fired.
	float vt = anim_state.y;
	float jitter = h2 * 0.35;
	int fire_mode = int(drill_state.y + 0.5);
	if (fire_mode > 0 && !staff) {
		float cyc = fire_mode == 1 ? PLATOON_CYCLE : AT_WILL_CYCLE;
		float first = drill_state.z + (fire_mode == 1 ? float(b.c - 1 - k) * PLATOON_CYCLE / float(b.c) : h4 * AT_WILL_CYCLE);
		vt = first + max(ceil((sim_time - 0.9 - first) / cyc), 0.0) * cyc;
		vt = vt <= drill_state.w ? vt : -1000.0;
		jitter = fire_mode == 1 ? jitter : 0.0;
	}
	float fire_rank = staff ? 0.0 : step(rank, 1.5) * (1.0 - moving);
	float present = fire_rank * smoothstep(vt - 1.6, vt - 1.1, sim_time) * (1.0 - smoothstep(vt + 0.3, vt + 0.9, sim_time));
	float shot_t = vt + jitter;
	float flash = fire_rank * step(shot_t, sim_time) * (1.0 - step(shot_t + 0.09, sim_time));

	int part = int(UV.y + 0.5);
	vec3 v = VERTEX;
	vec3 nrm = NORMAL;
	bool mounted = role == 3;
	// A company out skirmishing is drawn by its own formation, not here.
	int away_company = staff ? (i < 5 * b.c ? i / 5 : -1) : k;
	bool away = away_company >= 0 && ((int(form_state.w + 0.5) >> away_company) & 1) == 1;
	// Skirmishers have no colours, chef or adjutants with them.
	away = away || (staff && fb == OPEN && i >= 5 * b.c);
	if (away || ((mask >> part) & 1) == 0) {
		v = vec3(0.0, -50.0, 0.0);
	} else if (part == P_LEG_L || part == P_LEG_R) {
		if (mounted) {
			v.x += part == P_LEG_L ? -0.2 : 0.2; // astride the horse
		} else {
			v = rot_x(v, UV2, part == P_LEG_L ? swing : -swing);
		}
	} else if (part == P_HORSE_FORE || part == P_HORSE_HIND) {
		v = rot_x(v, UV2, part == P_HORSE_FORE ? swing * 0.8 : -swing * 0.8);
	} else if (part == P_MUSKET) {
		v = rot_x(v, UV2, -1.42 * present);
		nrm = rot_x(nrm, vec2(0.0), -1.42 * present);
	} else if (part == P_FLASH) {
		v = MUZZLE + (v - MUZZLE) * flash * 1.6;
		v = rot_x(v, UV2, -1.42 * present);
	} else if (part == P_CARD) {
		// Far tier card: turn to face the camera about the vertical axis.
		vec3 cam_local = transpose(mat3(MODEL_MATRIX)) * (INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec2 to_cam = cam_local.xz - pos;
		yaw = atan(-to_cam.x, to_cam.y);
	}
	if (mounted && (part < P_HORSE_FIRST || part > P_HORSE_HIND)) {
		v.y += 0.75;
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
	if (abs(v_part - 5.0) < 0.5) {
		ALBEDO = vec3(1.0, 0.8, 0.4);
		EMISSION = vec3(1.0, 0.55, 0.15) * 24.0;
	}
}
